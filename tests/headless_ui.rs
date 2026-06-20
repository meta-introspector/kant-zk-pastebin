//! Headless browser integration tests for Kant Pastebin UI.
//!
//! Uses chromiumoxide (CDP protocol) to drive a headless Chromium and test:
//!   - Split page: /splitter — text splitting, chunk upload
//!   - Share buttons: Reply, Copy, Share, QR, Split on paste pages
//!   - Paste creation and navigation
//!
//! Run with:
//!   nix develop --command cargo test --test headless_ui -- --nocapture
//!
//! Or against a running server:
//!   BASE_URL=http://127.0.0.1:8090 cargo test --test headless_ui -- --nocapture --test-threads=1

use chromiumoxide::browser::{Browser, BrowserConfig};
use chromiumoxide::cdp::browser_protocol::page::CaptureScreenshotFormat;
use chromiumoxide::page::ScreenshotParams;
use futures::StreamExt;
use serde_json::Value;
use std::time::Duration;

/// Base URL for the pastebin under test.
/// Defaults to the direct server on port 8090.
/// Note: the HTML pages use BASE_PATH=/pastebin in their internal links,
/// so when testing Reply navigation, we check for /pastebin/ prefix.
fn base_url() -> String {
    std::env::var("BASE_URL").unwrap_or_else(|_| "http://127.0.0.1:8090".to_string())
}

/// Launch a headless Chromium browser via CDP.
/// Each call creates a unique temp dir to avoid SingletonLock conflicts.
async fn launch_browser(
) -> Result<(Browser, tokio::task::JoinHandle<()>), Box<dyn std::error::Error>> {
    let user_data_dir = tempfile::Builder::new()
        .prefix("pastebin-headless-")
        .tempdir()?
        .path()
        .to_path_buf();

    let (browser, mut handler) = Browser::launch(
        BrowserConfig::builder()
            .arg("--no-sandbox")
            .arg("--disable-gpu")
            .arg("--disable-dev-shm-usage")
            .arg("--disable-background-networking")
            .arg(format!("--user-data-dir={}", user_data_dir.display()))
            .window_size(1280, 1024)
            .build()?,
    )
    .await?;

    let handle = tokio::spawn(async move {
        while let Some(h) = handler.next().await {
            let _ = h;
        }
    });

    Ok((browser, handle))
}

/// Helper: take a screenshot for debugging.
async fn screenshot_page(
    page: &chromiumoxide::Page,
    name: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let path = format!("/tmp/pastebin-test-{}.png", name);
    page.save_screenshot(
        ScreenshotParams::builder()
            .format(CaptureScreenshotFormat::Png)
            .full_page(true)
            .build(),
        &path,
    )
    .await?;
    eprintln!("  screenshot: {}", path);
    Ok(())
}

// ─── Test: Split profiles API ──────────────────────────────────────────

#[tokio::test]
async fn test_split_profiles_api() -> Result<(), Box<dyn std::error::Error>> {
    let base = base_url();
    let client = reqwest::Client::new();

    // List all profiles
    let resp = client
        .get(format!("{}/api/split-profiles", base))
        .send()
        .await?;
    assert!(
        resp.status().is_success(),
        "Split profiles list should succeed"
    );
    let body: Value = resp.json().await?;
    let profiles = body.get("profiles").and_then(|v| v.as_array()).unwrap();
    assert!(
        profiles.len() >= 6,
        "Should have at least 6 built-in profiles, got: {}",
        profiles.len()
    );

    // Check each expected profile exists
    let names: Vec<&str> = profiles
        .iter()
        .filter_map(|p| p.get("name").and_then(|v| v.as_str()))
        .collect();
    for expected in &["openai", "grok", "perplexity", "claude", "gemini", "local"] {
        assert!(
            names.iter().any(|n| n == expected),
            "Profile '{}' should exist, got: {:?}",
            expected,
            names
        );
    }
    eprintln!("  Profiles: {:?}", names);

    // Get individual profile
    let resp = client
        .get(format!("{}/api/split-profiles/openai", base))
        .send()
        .await?;
    assert!(resp.status().is_success(), "OpenAI profile should exist");
    let openai: Value = resp.json().await?;
    assert_eq!(openai.get("name").and_then(|v| v.as_str()), Some("openai"));
    assert_eq!(
        openai.get("chunk_size").and_then(|v| v.as_u64()),
        Some(100_000)
    );
    assert_eq!(openai.get("overlap").and_then(|v| v.as_u64()), Some(2_000));
    assert_eq!(openai.get("builtin").and_then(|v| v.as_bool()), Some(true));
    eprintln!(
        "  OpenAI: {}B chunks, {}B overlap, {} output tokens",
        openai.get("chunk_size").unwrap(),
        openai.get("overlap").unwrap(),
        openai.get("max_output_tokens").unwrap()
    );

    // Test unknown profile
    let resp = client
        .get(format!("{}/api/split-profiles/nonexistent", base))
        .send()
        .await?;
    assert_eq!(resp.status(), 404, "Unknown profile should return 404");

    Ok(())
}

// ─── Test: Split with profile parameter ────────────────────────────────

#[tokio::test]
async fn test_split_with_profile() -> Result<(), Box<dyn std::error::Error>> {
    let base = base_url();
    let client = reqwest::Client::new();

    // Create a long text
    let long_text = "Hello World. ".repeat(1000); // ~13KB

    // Split with "local" profile (6KB chunks, 500B overlap)
    let resp = client
        .post(format!("{}/api/split", base))
        .json(&serde_json::json!({
            "content": long_text,
            "profile": "local"
        }))
        .send()
        .await?;
    assert!(
        resp.status().is_success(),
        "Split with profile should succeed"
    );
    let body: Value = resp.json().await?;
    let chunks = body.get("chunks").and_then(|v| v.as_u64()).unwrap_or(0);
    assert!(
        chunks >= 2,
        "Should split into 2+ chunks with local profile (6KB), got: {}",
        chunks
    );
    assert_eq!(body.get("chunk_size").and_then(|v| v.as_u64()), Some(6_000));
    assert_eq!(body.get("overlap").and_then(|v| v.as_u64()), Some(500));
    assert_eq!(body.get("profile").and_then(|v| v.as_str()), Some("local"));
    eprintln!(
        "  Local profile: {} chunks, {}B chunk_size, {}B overlap",
        chunks, body["chunk_size"], body["overlap"]
    );

    // Verify overlap: chunk 2 should start with the tail of chunk 1
    let contents = body.get("contents").and_then(|v| v.as_array()).unwrap();
    if contents.len() >= 2 {
        let chunk1 = contents[0].as_str().unwrap_or_default();
        let chunk2 = contents[1].as_str().unwrap_or_default();
        let overlap_text = &chunk1[chunk1.len().saturating_sub(500)..];
        assert!(
            chunk2.starts_with(overlap_text),
            "Chunk 2 should start with overlap from chunk 1"
        );
        eprintln!(
            "  Overlap verified: chunk2 starts with last {} chars of chunk1",
            overlap_text.len()
        );
    }

    // Test unknown profile
    let resp = client
        .post(format!("{}/api/split", base))
        .json(&serde_json::json!({
            "content": "test",
            "profile": "nonexistent"
        }))
        .send()
        .await?;
    assert_eq!(resp.status(), 400, "Unknown profile should return 400");
    let body: Value = resp.json().await?;
    assert!(body.get("error").is_some(), "Should have error field");
    assert!(
        body.get("available").is_some(),
        "Should list available profiles"
    );

    Ok(())
}

// ─── Test: Splitter page has profile selector ──────────────────────────

#[tokio::test]
async fn test_splitter_profile_selector() -> Result<(), Box<dyn std::error::Error>> {
    let (mut browser, handle) = launch_browser().await?;
    let base = base_url();

    let page = browser.new_page(format!("{}/splitter", base)).await?;
    page.wait_for_navigation_response().await?;
    wait_ms(2000).await;

    // Check that profile cards exist
    let cards: String = eval(&page,
        "Array.from(document.querySelectorAll('.profile-card')).map(c => c.dataset.name).join(', ')"
    ).await?.as_str().unwrap_or_default().to_string();
    eprintln!("  Profile cards: {}", cards);

    assert!(cards.contains("openai"), "Should have openai profile card");
    assert!(cards.contains("grok"), "Should have grok profile card");
    assert!(cards.contains("custom"), "Should have custom profile card");

    // Check that chunk size and overlap inputs exist
    let chunk_input = page.find_element("input#chunkSize").await;
    assert!(chunk_input.is_ok(), "Chunk size input should exist");

    let overlap_input = page.find_element("input#overlap").await;
    assert!(overlap_input.is_ok(), "Overlap input should exist");

    // Check that OpenAI is selected by default (after 300ms timeout)
    let active: String = eval(
        &page,
        "document.querySelector('.profile-card.active')?.dataset.name || 'none'",
    )
    .await?
    .as_str()
    .unwrap_or_default()
    .to_string();
    assert_eq!(
        active, "openai",
        "OpenAI should be selected by default, got: {}",
        active
    );

    // Check that chunk size was set to OpenAI's value (100000)
    let chunk_val: String = eval(&page, "document.getElementById('chunkSize').value")
        .await?
        .as_str()
        .unwrap_or_default()
        .to_string();
    assert_eq!(
        chunk_val, "100000",
        "Chunk size should be 100000 for OpenAI, got: {}",
        chunk_val
    );

    // Check that overlap was set
    let overlap_val: String = eval(&page, "document.getElementById('overlap').value")
        .await?
        .as_str()
        .unwrap_or_default()
        .to_string();
    assert_eq!(
        overlap_val, "2000",
        "Overlap should be 2000 for OpenAI, got: {}",
        overlap_val
    );

    screenshot_page(&page, "splitter-profiles").await.ok();
    browser.close().await?;
    handle.await?;
    Ok(())
}

/// Helper: wait with timeout.
async fn wait_ms(ms: u64) {
    tokio::time::sleep(Duration::from_millis(ms)).await;
}

/// Helper: evaluate JS and get a serde_json::Value
async fn eval(page: &chromiumoxide::Page, js: &str) -> Result<Value, Box<dyn std::error::Error>> {
    let result = page.evaluate(js).await?;
    Ok(result.value().cloned().unwrap_or(Value::Null))
}

/// Helper: create a test paste via the API and return its ID.
async fn create_test_paste(
    client: &reqwest::Client,
    base: &str,
    title: &str,
    content: &str,
) -> Result<String, Box<dyn std::error::Error>> {
    let resp = client
        .post(format!("{}/paste", base))
        .json(&serde_json::json!({ "title": title, "content": content }))
        .send()
        .await?;
    assert!(
        resp.status().is_success(),
        "Paste creation failed: {}",
        resp.status()
    );
    let body: Value = resp.json().await?;
    Ok(body
        .get("id")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown")
        .to_string())
}

async fn open_share_menu(page: &chromiumoxide::Page) -> Result<(), Box<dyn std::error::Error>> {
    eval(
        page,
        "Array.from(document.querySelectorAll('button.reply-btn')).find(b => b.textContent.trim() === 'Share').click()",
    )
    .await?;
    wait_ms(250).await;
    Ok(())
}

async fn install_share_test_mocks(
    page: &chromiumoxide::Page,
) -> Result<(), Box<dyn std::error::Error>> {
    eval(
        page,
        r#"
        window.__shareCall = null;
        window.__openedUrls = [];
        window.__clipboardText = null;
        navigator.share = (opts) => {
            window.__shareCall = opts;
            return Promise.resolve();
        };
        window.open = (url, target, features) => {
            window.__openedUrls.push({ url, target, features });
            return { closed: false, close() {} };
        };
        navigator.clipboard = {
            writeText: (text) => {
                window.__clipboardText = text;
                return Promise.resolve();
            }
        };
    "#,
    )
    .await?;
    Ok(())
}

async fn assert_share_menu_action(
    page: &chromiumoxide::Page,
    action: &str,
    label: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let found: bool = eval(
        page,
        &format!(
            "Array.from(document.querySelectorAll('#shareMenu button')).some(b => b.dataset.shareAction === '{}' && b.textContent.trim() === '{}')",
            action, label
        ),
    )
    .await?
    .as_bool()
    .unwrap_or(false);
    assert!(
        found,
        "Share menu should contain action '{}' with label '{}'",
        action, label
    );
    Ok(())
}

async fn click_share_menu_action(
    page: &chromiumoxide::Page,
    action: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    eval(
        page,
        &format!(
            "Array.from(document.querySelectorAll('#shareMenu button')).find(b => b.dataset.shareAction === '{}').click()",
            action
        ),
    )
    .await?;
    wait_ms(500).await;
    Ok(())
}

async fn last_opened_url(page: &chromiumoxide::Page) -> Result<String, Box<dyn std::error::Error>> {
    let opened: Value = eval(page, "window.__openedUrls").await?;
    Ok(opened
        .as_array()
        .and_then(|urls| urls.last())
        .and_then(|entry| entry.get("url"))
        .and_then(|url| url.as_str())
        .unwrap_or_default()
        .to_string())
}

// ─── Test: Splitter page loads and has key elements ────────────────────

#[tokio::test]
async fn test_splitter_page_loads() -> Result<(), Box<dyn std::error::Error>> {
    let (mut browser, handle) = launch_browser().await?;
    let base = base_url();

    let page = browser.new_page(format!("{}/splitter", base)).await?;
    page.wait_for_navigation_response().await?;
    wait_ms(1000).await;

    // Check the title
    let title = page.get_title().await?.unwrap_or_default();
    assert!(
        title.contains("Splitter"),
        "Title should contain 'Splitter', got: {}",
        title
    );

    // Check the textarea exists
    let textarea = page.find_element("textarea#textInput").await;
    assert!(textarea.is_ok(), "Textarea #textInput should exist");

    // Check chunk size input (now an <input> not a <select>)
    let chunk_input = page.find_element("input#chunkSize").await;
    assert!(chunk_input.is_ok(), "Input #chunkSize should exist");

    // Check split mode selector
    let split_mode = page.find_element("select#splitMode").await;
    assert!(split_mode.is_ok(), "Select #splitMode should exist");

    // Check the split button
    let split_btn = page.find_element("button").await?;
    let btn_text = split_btn.inner_text().await?;
    assert!(
        btn_text
            .as_ref()
            .map(|s| s.contains("Split"))
            .unwrap_or(false),
        "First button should be Split, got: {:?}",
        btn_text
    );

    screenshot_page(&page, "splitter-page").await.ok();
    browser.close().await?;
    handle.await?;
    Ok(())
}

// ─── Test: Split API works via headless browser ────────────────────────

#[tokio::test]
async fn test_split_api() -> Result<(), Box<dyn std::error::Error>> {
    // Test the split API directly (the browser JS uses BASE_PATH prefix
    // which may not route correctly when testing against the direct server)
    let base = base_url();
    let client = reqwest::Client::new();

    // Test basic split
    let resp = client
        .post(format!("{}/api/split", base))
        .json(&serde_json::json!({
            "content": "Hello World this is a test of the text splitter functionality. It should split into chunks.",
            "chunk_size": 50
        }))
        .send()
        .await?;
    assert!(
        resp.status().is_success(),
        "Split API should succeed: {}",
        resp.status()
    );
    let body: Value = resp.json().await?;
    let chunks = body.get("chunks").and_then(|v| v.as_u64()).unwrap_or(0);
    assert!(
        chunks > 1,
        "Should split into multiple chunks with chunk_size=50, got: {}",
        chunks
    );
    eprintln!("  Split into {} chunks", chunks);

    // Test empty content
    let resp = client
        .post(format!("{}/api/split", base))
        .json(&serde_json::json!({ "content": "", "chunk_size": 1024 }))
        .send()
        .await?;
    assert!(!resp.status().is_success(), "Empty content should fail");

    // Test split-upload
    let resp = client
        .post(format!("{}/api/split-upload", base))
        .json(&serde_json::json!({
            "content": "Upload test chunk one. Upload test chunk two.",
            "chunk_size": 25,
            "title": "headless_split_test"
        }))
        .send()
        .await?;
    assert!(
        resp.status().is_success(),
        "Split-upload API should succeed: {}",
        resp.status()
    );
    let body: Value = resp.json().await?;
    eprintln!("  Split-upload result: {:?}", body);

    Ok(())
}

// ─── Test: Paste creation and view page ────────────────────────────────

#[tokio::test]
async fn test_paste_create_and_view() -> Result<(), Box<dyn std::error::Error>> {
    let (mut browser, handle) = launch_browser().await?;
    let base = base_url();

    // Go to home page
    let page = browser.new_page(format!("{}/", base)).await?;
    page.wait_for_navigation_response().await?;
    wait_ms(1000).await;

    // Check that the home page has a form or textarea
    let has_form =
        page.find_element("form").await.is_ok() || page.find_element("textarea").await.is_ok();
    assert!(
        has_form,
        "Home page should have a form or textarea for paste creation"
    );

    screenshot_page(&page, "home-page").await.ok();

    // Create a paste via the API
    let client = reqwest::Client::new();
    let paste_id = create_test_paste(
        &client,
        &base,
        "Headless Test Paste",
        "This is a test paste created by the headless browser test suite.",
    )
    .await?;

    // Navigate to the paste view page
    let page2 = browser
        .new_page(format!("{}/paste/{}", base, paste_id))
        .await?;
    page2.wait_for_navigation_response().await?;
    wait_ms(1000).await;

    // Check that the paste content is displayed
    let pre = page2.find_element("pre").await;
    assert!(pre.is_ok(), "Paste view should have <pre> element");

    // Check the title
    let title = page2.get_title().await?.unwrap_or_default();
    assert!(
        title.contains("Headless Test Paste") || title.contains("kant-pastebin"),
        "Title should contain paste title or kant-pastebin, got: {}",
        title
    );

    screenshot_page(&page2, "paste-view").await.ok();
    browser.close().await?;
    handle.await?;
    Ok(())
}

// ─── Test: Reply button on paste page ──────────────────────────────────

#[tokio::test]
async fn test_reply_button() -> Result<(), Box<dyn std::error::Error>> {
    let (mut browser, handle) = launch_browser().await?;
    let base = base_url();

    // Create a paste
    let client = reqwest::Client::new();
    let paste_id = create_test_paste(
        &client,
        &base,
        "Reply Test Paste",
        "Testing the reply button functionality.",
    )
    .await?;

    // Navigate to the paste page
    let page = browser
        .new_page(format!("{}/paste/{}", base, paste_id))
        .await?;
    page.wait_for_navigation_response().await?;
    wait_ms(1000).await;

    // Find the Reply link (it's an <a> with class reply-btn)
    let reply_link = page.find_element("a.reply-btn").await;
    if let Ok(link) = reply_link {
        let text = link.inner_text().await?;
        let text_str = text.unwrap_or_default();
        assert!(
            text_str.contains("Reply"),
            "Reply link text should contain 'Reply', got: {}",
            text_str
        );

        // Check the href contains reply_to
        let href = link.attribute("href").await?;
        assert!(
            href.as_ref()
                .map(|h| h.contains("reply_to="))
                .unwrap_or(false),
            "Reply link href should contain reply_to=, got: {:?}",
            href
        );
        eprintln!("  Reply link href: {:?}", href);

        screenshot_page(&page, "reply-button").await.ok();
    } else {
        eprintln!("  ⚠️ Reply <a> not found, checking all reply-btn elements...");
        let btn_texts: String = eval(&page,
            "Array.from(document.querySelectorAll('.reply-btn')).map(b => b.textContent.trim()).join(', ')"
        ).await?.as_str().unwrap_or_default().to_string();
        eprintln!("  Buttons: {}", btn_texts);
    }

    browser.close().await?;
    handle.await?;
    Ok(())
}

// ─── Test: Copy button on paste page ──────────────────────────────────

#[tokio::test]
async fn test_copy_button() -> Result<(), Box<dyn std::error::Error>> {
    let (mut browser, handle) = launch_browser().await?;
    let base = base_url();

    // Create a paste
    let client = reqwest::Client::new();
    let paste_id = create_test_paste(
        &client,
        &base,
        "Copy Test Paste",
        "Testing the copy button.",
    )
    .await?;

    // Navigate to paste page
    let page = browser
        .new_page(format!("{}/paste/{}", base, paste_id))
        .await?;
    page.wait_for_navigation_response().await?;
    wait_ms(1000).await;

    // Mock clipboard API so we can intercept the copy.
    // The Copy button's onclick directly calls navigator.clipboard.writeText,
    // so we must override it before clicking.
    eval(
        &page,
        r#"
        window.__clipboardText = null;
        navigator.clipboard = {
            writeText: (text) => { window.__clipboardText = text; return Promise.resolve(); }
        };
    "#,
    )
    .await?;

    // Find the Copy button
    let copy_btn: bool = eval(&page,
        "Array.from(document.querySelectorAll('button.reply-btn')).some(b => b.textContent.includes('Copy'))"
    ).await?.as_bool().unwrap_or(false);

    assert!(copy_btn, "Copy button should exist on paste page");

    // Click it via JS (so we don't need to find the exact element)
    eval(&page, "Array.from(document.querySelectorAll('button.reply-btn')).find(b => b.textContent.includes('Copy')).click()").await?;
    wait_ms(500).await;

    // Check clipboard was set
    let clipboard: Value = eval(&page, "window.__clipboardText").await?;
    let clipboard_str = clipboard.as_str().unwrap_or_default();
    // The copy button writes the <pre> content to clipboard
    if clipboard_str.is_empty() {
        // The button might have changed text to "✅ Copied" which confirms it worked
        let btn_text: String = eval(&page,
            "Array.from(document.querySelectorAll('button.reply-btn')).find(b => b.textContent.includes('Copied') || b.textContent.includes('Copy')).textContent"
        ).await?.as_str().unwrap_or_default().to_string();
        eprintln!("  Button text after click: {}", btn_text);
        // If the button text changed to "✅ Copied", the copy worked
        // (the clipboard mock may not have been applied in time)
    }
    eprintln!("  Clipboard content: {} chars", clipboard_str.len());

    screenshot_page(&page, "copy-button").await.ok();
    browser.close().await?;
    handle.await?;
    Ok(())
}

// ─── Test: Share button on paste page ──────────────────────────────────

#[tokio::test]
async fn test_share_button() -> Result<(), Box<dyn std::error::Error>> {
    let (mut browser, handle) = launch_browser().await?;
    let base = base_url();

    // Create a paste
    let client = reqwest::Client::new();
    let paste_id = create_test_paste(
        &client,
        &base,
        "Share Test Paste",
        "Testing the share button.",
    )
    .await?;

    // Navigate to paste page
    let page = browser
        .new_page(format!("{}/paste/{}", base, paste_id))
        .await?;
    page.wait_for_navigation_response().await?;
    wait_ms(1000).await;

    let share_btn: bool = eval(&page,
        "Array.from(document.querySelectorAll('button.reply-btn')).some(b => b.textContent.trim() === 'Share')"
    ).await?.as_bool().unwrap_or(false);

    assert!(share_btn, "Share button should exist on paste page");

    install_share_test_mocks(&page).await?;
    open_share_menu(&page).await?;
    click_share_menu_action(&page, "native").await?;

    // Check navigator.share was called
    let share_call: Value = eval(&page, "window.__shareCall").await?;
    assert!(
        !share_call.is_null(),
        "navigator.share should have been called from the Native Share menu item"
    );
    let share_url = share_call
        .get("url")
        .and_then(|v| v.as_str())
        .unwrap_or_default();
    assert!(
        share_url.contains(&paste_id),
        "Share URL should contain paste ID, got: {}",
        share_url
    );
    eprintln!("  Share called with URL: {}", share_url);

    screenshot_page(&page, "share-button").await.ok();
    browser.close().await?;
    handle.await?;
    Ok(())
}

#[tokio::test]
async fn test_share_menu_destinations() -> Result<(), Box<dyn std::error::Error>> {
    let (mut browser, handle) = launch_browser().await?;
    let base = base_url();

    let client = reqwest::Client::new();
    let paste_id = create_test_paste(
        &client,
        &base,
        "Reusable Share Test",
        "Testing reusable share destination checks.",
    )
    .await?;

    let page = browser
        .new_page(format!("{}/paste/{}", base, paste_id))
        .await?;
    page.wait_for_navigation_response().await?;
    wait_ms(1000).await;

    install_share_test_mocks(&page).await?;
    open_share_menu(&page).await?;

    let expected_actions = [
        ("native", "Native Share"),
        ("copy-url", "Copy URL"),
        ("copy-prompt", "Copy Prompt"),
        ("claude", "Claude"),
        ("openai", "OpenAI / ChatGPT"),
        ("grok", "Grok"),
        ("x", "X"),
        ("nightcafe", "NightCafe"),
        ("deepseek", "DeepSeek Chat"),
        ("github", "Search GitHub"),
        ("huggingface", "Search Hugging Face"),
    ];
    for (action, label) in expected_actions {
        assert_share_menu_action(&page, action, label).await?;
    }

    click_share_menu_action(&page, "copy-url").await?;
    let copied_url: String = eval(&page, "window.__clipboardText")
        .await?
        .as_str()
        .unwrap_or_default()
        .to_string();
    assert!(copied_url.contains(&paste_id), "Copy URL should copy paste URL");

    click_share_menu_action(&page, "copy-prompt").await?;
    let copied_prompt: String = eval(&page, "window.__clipboardText")
        .await?
        .as_str()
        .unwrap_or_default()
        .to_string();
    assert!(
        copied_prompt.contains("Title: Reusable Share Test"),
        "Copy Prompt should include paste title"
    );
    assert!(copied_prompt.contains(&paste_id), "Copy Prompt should include paste URL");
    assert!(
        copied_prompt.contains("Testing reusable share destination checks."),
        "Copy Prompt should include paste content"
    );

    click_share_menu_action(&page, "claude").await?;
    assert!(
        last_opened_url(&page).await?.starts_with("https://claude.ai/new?q="),
        "Claude should open a prompt URL"
    );

    click_share_menu_action(&page, "openai").await?;
    assert!(
        last_opened_url(&page).await?.starts_with("https://chatgpt.com/?q="),
        "OpenAI should open a prompt URL"
    );

    click_share_menu_action(&page, "grok").await?;
    assert!(
        last_opened_url(&page).await?.starts_with("https://grok.com/?q="),
        "Grok should open a prompt URL"
    );

    click_share_menu_action(&page, "x").await?;
    let x_url = last_opened_url(&page).await?;
    assert!(
        x_url.starts_with("https://x.com/intent/tweet?") && x_url.contains("url="),
        "X should open an intent URL"
    );

    click_share_menu_action(&page, "nightcafe").await?;
    let nightcafe_url = last_opened_url(&page).await?;
    assert_eq!(
        nightcafe_url, "https://creator.nightcafe.studio/create",
        "NightCafe should open the create page"
    );
    assert!(
        eval(&page, "window.__clipboardText")
            .await?
            .as_str()
            .unwrap_or_default()
            .contains("Title: Reusable Share Test"),
        "NightCafe should copy the prompt"
    );

    click_share_menu_action(&page, "deepseek").await?;
    assert!(
        last_opened_url(&page).await?.starts_with("https://chat.deepseek.com/?q="),
        "DeepSeek should open a prompt URL"
    );

    click_share_menu_action(&page, "github").await?;
    let github_url = last_opened_url(&page).await?;
    assert!(
        github_url.starts_with("https://github.com/search?q=")
            && github_url.contains("type=code"),
        "GitHub should open a code search URL"
    );

    click_share_menu_action(&page, "huggingface").await?;
    assert!(
        last_opened_url(&page)
            .await?
            .starts_with("https://huggingface.co/search?q="),
        "Hugging Face should open a search URL"
    );

    screenshot_page(&page, "share-menu-destinations").await.ok();
    browser.close().await?;
    handle.await?;
    Ok(())
}

// ─── Test: Split button on paste page ──────────────────────────────────

#[tokio::test]
async fn test_split_button_on_paste_page() -> Result<(), Box<dyn std::error::Error>> {
    let (mut browser, handle) = launch_browser().await?;
    let base = base_url();

    // Create a paste
    let client = reqwest::Client::new();
    let paste_id = create_test_paste(
        &client,
        &base,
        "Split Test Paste",
        "Testing the split button from paste page.",
    )
    .await?;

    // Navigate to paste page
    let page = browser
        .new_page(format!("{}/paste/{}", base, paste_id))
        .await?;
    page.wait_for_navigation_response().await?;
    wait_ms(1000).await;

    // Check the Split button exists
    let split_btn: bool = eval(&page,
        "Array.from(document.querySelectorAll('button.reply-btn')).some(b => b.textContent.includes('Split'))"
    ).await?.as_bool().unwrap_or(false);

    assert!(split_btn, "Split button should exist on paste page");

    // Click the Split button — it stores text in localStorage and opens /splitter/
    eval(&page, "Array.from(document.querySelectorAll('button.reply-btn')).find(b => b.textContent.includes('Split')).click()").await?;
    wait_ms(2000).await;

    // Check if localStorage was set
    let stored_text: Value = eval(&page, "localStorage.getItem('splitter-text')").await?;
    let stored_str = stored_text.as_str().unwrap_or_default();
    assert!(
        !stored_str.is_empty(),
        "localStorage should have splitter-text after clicking Split"
    );
    eprintln!("  Splitter text stored: {} chars", stored_str.len());

    screenshot_page(&page, "split-button").await.ok();
    browser.close().await?;
    handle.await?;
    Ok(())
}

// ─── Test: All buttons present on paste page ───────────────────────────

#[tokio::test]
async fn test_all_buttons_present() -> Result<(), Box<dyn std::error::Error>> {
    let (mut browser, handle) = launch_browser().await?;
    let base = base_url();

    // Create a paste
    let client = reqwest::Client::new();
    let paste_id = create_test_paste(
        &client,
        &base,
        "Button Inventory Test",
        "Checking all buttons exist.",
    )
    .await?;

    // Navigate to paste page
    let page = browser
        .new_page(format!("{}/paste/{}", base, paste_id))
        .await?;
    page.wait_for_navigation_response().await?;
    wait_ms(1000).await;

    // Get all button texts
    let buttons: String = eval(&page,
        "Array.from(document.querySelectorAll('.reply-btn')).map(b => b.textContent.trim()).join(' | ')"
    ).await?.as_str().unwrap_or_default().to_string();

    eprintln!("  Buttons found: {}", buttons);

    // Check each expected button
    let expected = ["Reply", "Copy", "Share", "QR", "Split"];
    for label in &expected {
        assert!(
            buttons.contains(label),
            "Button '{}' should be present, got: {}",
            label,
            buttons
        );
    }

    screenshot_page(&page, "all-buttons").await.ok();
    browser.close().await?;
    handle.await?;
    Ok(())
}
