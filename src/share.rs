use std::fmt::Write as _;

#[derive(Clone, Copy)]
pub struct ShareAction {
    pub action: &'static str,
    pub label: &'static str,
}

pub const SHARE_ACTIONS: &[ShareAction] = &[
    ShareAction {
        action: "native",
        label: "Native Share",
    },
    ShareAction {
        action: "copy-url",
        label: "Copy URL",
    },
    ShareAction {
        action: "copy-prompt",
        label: "Copy Prompt",
    },
    ShareAction {
        action: "claude",
        label: "Claude",
    },
    ShareAction {
        action: "openai",
        label: "OpenAI / ChatGPT",
    },
    ShareAction {
        action: "grok",
        label: "Grok",
    },
    ShareAction {
        action: "x",
        label: "X",
    },
    ShareAction {
        action: "nightcafe",
        label: "NightCafe",
    },
    ShareAction {
        action: "deepseek",
        label: "DeepSeek Chat",
    },
    ShareAction {
        action: "github",
        label: "Search GitHub",
    },
    ShareAction {
        action: "huggingface",
        label: "Search Hugging Face",
    },
];

pub fn render_share_menu() -> String {
    let mut html = String::from(
        r#"<div class="share-wrap">
  <button class="reply-btn" id="shareMenuButton" onclick="toggleShareMenu()">Share</button>
  <div class="share-menu" id="shareMenu">
"#,
    );

    for action in SHARE_ACTIONS {
        let _ = writeln!(
            html,
            "    <button data-share-action=\"{}\">{}</button>",
            action.action, action.label
        );
    }

    html.push_str("  </div>\n</div>");
    html
}

pub fn render_share_script() -> &'static str {
    r#"
function copyShareUrl() {
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(pasteUrl).then(() => alert('Paste URL copied:\n\n' + pasteUrl)).catch(() => alert(pasteUrl));
  } else {
    alert(pasteUrl);
  }
}

function sharePost() {
  if (navigator.share) {
    navigator.share({title: title, url: pasteUrl, text: 'Check out this paste: ' + pasteUrl}).catch(copyShareUrl);
  } else {
    copyShareUrl();
  }
}

function getSharePrompt() {
  const pre = document.querySelector('pre');
  const content = pre ? (pre.textContent || '') : '';
  const maxChars = 4000;
  const excerpt = content.length > maxChars ? content.slice(0, maxChars) + '\n\n[content truncated for URL length]' : content;
  return 'Title: ' + title + '\nURL: ' + pasteUrl + '\n\n' + excerpt;
}

function fallbackCopyText(text) {
  const textarea = document.createElement('textarea');
  textarea.value = text;
  textarea.setAttribute('readonly', '');
  textarea.style.position = 'fixed';
  textarea.style.left = '-9999px';
  document.body.appendChild(textarea);
  textarea.select();
  let copied = false;
  try { copied = document.execCommand('copy'); } catch (e) {}
  document.body.removeChild(textarea);
  if (copied) { alert('Share prompt copied.'); } else { alert(text.slice(0, 1000)); }
}

function copyText(text) {
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text).then(() => alert('Share prompt copied.')).catch(() => fallbackCopyText(text));
  } else {
    fallbackCopyText(text);
  }
}

function toggleShareMenu() {
  const menu = document.getElementById('shareMenu');
  if (menu) { menu.classList.toggle('open'); }
}

function hideShareMenu() {
  const menu = document.getElementById('shareMenu');
  if (menu) { menu.classList.remove('open'); }
}

function openShareUrl(url) {
  window.open(url, '_blank', 'noopener,noreferrer');
}

function shareToDestination(action) {
  const prompt = getSharePrompt();
  const pre = document.querySelector('pre');
  const searchQuery = title + ' ' + (pre ? (pre.textContent || '').slice(0, 1000) : '');
  let url = '';

  if (action === 'native') {
    sharePost();
    hideShareMenu();
    return;
  }
  if (action === 'copy-url') {
    copyShareUrl();
    hideShareMenu();
    return;
  }
  if (action === 'copy-prompt') {
    copyText(prompt);
    hideShareMenu();
    return;
  }
  if (action === 'nightcafe') {
    copyText(prompt);
    url = 'https://creator.nightcafe.studio/create';
  } else if (action === 'claude') {
    url = 'https://claude.ai/new?q=' + encodeURIComponent(prompt);
  } else if (action === 'openai') {
    url = 'https://chatgpt.com/?q=' + encodeURIComponent(prompt);
  } else if (action === 'grok') {
    url = 'https://grok.com/?q=' + encodeURIComponent(prompt);
  } else if (action === 'x') {
    url = 'https://x.com/intent/tweet?text=' + encodeURIComponent('Check out this paste: ' + pasteUrl) + '&url=' + encodeURIComponent(pasteUrl);
  } else if (action === 'deepseek') {
    url = 'https://chat.deepseek.com/?q=' + encodeURIComponent(prompt);
  } else if (action === 'github') {
    url = 'https://github.com/search?q=' + encodeURIComponent(searchQuery) + '&type=code';
  } else if (action === 'huggingface') {
    url = 'https://huggingface.co/search?q=' + encodeURIComponent(searchQuery);
  }

  if (url) { openShareUrl(url); }
  hideShareMenu();
}

document.querySelectorAll('[data-share-action]').forEach(function(button) {
  button.addEventListener('click', function() { shareToDestination(button.getAttribute('data-share-action')); });
});
document.addEventListener('click', function(event) {
  const menu = document.getElementById('shareMenu');
  const button = document.getElementById('shareMenuButton');
  if (menu && button && !menu.contains(event.target) && !button.contains(event.target)) { hideShareMenu(); }
});
document.addEventListener('keydown', function(event) {
  if (event.key === 'Escape') { hideShareMenu(); }
});
"#
}

pub fn run_share_menu_test() -> Result<(), String> {
    let html = render_share_menu();
    let script = render_share_script();

    for action in SHARE_ACTIONS {
        let marker = format!("data-share-action=\"{}\"", action.action);
        if !html.contains(&marker) {
            return Err(format!("share menu is missing action '{}'", action.action));
        }
        if !html.contains(action.label) {
            return Err(format!("share menu is missing label '{}'", action.label));
        }
    }

    let expected_fragments = [
        ("native", "sharePost()"),
        ("copy-url", "copyShareUrl()"),
        ("copy-prompt", "copyText(prompt)"),
        ("claude", "https://claude.ai/new?q="),
        ("openai", "https://chatgpt.com/?q="),
        ("grok", "https://grok.com/?q="),
        ("x", "https://x.com/intent/tweet?text="),
        ("nightcafe", "https://creator.nightcafe.studio/create"),
        ("deepseek", "https://chat.deepseek.com/?q="),
        ("github", "https://github.com/search?q="),
        ("huggingface", "https://huggingface.co/search?q="),
    ];

    for (action, fragment) in expected_fragments {
        if !script.contains(fragment) {
            return Err(format!(
                "share script is missing '{}' fragment '{}'",
                action, fragment
            ));
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn share_menu_artifacts_cover_expected_destinations() {
        run_share_menu_test().expect("share menu artifacts should cover expected destinations");
    }
}
