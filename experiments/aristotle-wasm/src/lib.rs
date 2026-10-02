use wasm_bindgen::prelude::*;
use wasm_bindgen_futures::JsFuture;
use web_sys::window;
use console_error_panic_hook::set_once as set_panic_hook;

#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(js_namespace = console)]
    fn log(s: &str);
}

#[wasm_bindgen]
pub fn init_panic_hook() {
    set_panic_hook();
}

static mut API_KEY: Option<String> = None;

#[wasm_bindgen]
pub fn set_api_key(key: &str) {
    unsafe {
        API_KEY = Some(key.to_string());
    }
    log(&format!("API key set (length: {})", key.len()));
}

#[wasm_bindgen]
pub fn get_api_key() -> Option<String> {
    unsafe { API_KEY.clone() }
}

#[wasm_bindgen]
pub fn get_api_base_url() -> String {
    "https://aristotle.harmonic.fun/api/v3".to_string()
}

#[wasm_bindgen]
pub async fn fetch_project(project_id: &str) -> Result<JsValue, JsValue> {
    let api_key = match unsafe { API_KEY.as_ref() } {
        Some(key) => key.clone(),
        None => return Err("API key not set".into()),
    };

    let url = format!("https://aristotle.harmonic.fun/api/v3/project/{}", project_id);
    fetch_json(&url, &api_key).await
}

#[wasm_bindgen]
pub async fn fetch_project_list() -> Result<JsValue, JsValue> {
    let api_key = match unsafe { API_KEY.as_ref() } {
        Some(key) => key.clone(),
        None => return Err("API key not set".into()),
    };

    let url = "https://aristotle.harmonic.fun/api/v3/project";
    fetch_json(&url, &api_key).await
}

async fn fetch_json(url: &str, api_key: &str) -> Result<JsValue, JsValue> {
    let mut opts = web_sys::RequestInit::new();
    opts.set_method("GET");
    opts.set_mode(web_sys::RequestMode::Cors);

    let headers = web_sys::Headers::new().map_err(|_| "Failed to create headers")?;
    headers.set("x-api-key", api_key).map_err(|_| "Failed to set header")?;
    opts.set_headers(&headers);

    let request = web_sys::Request::new_with_str_and_init(url, &opts)
        .map_err(|_| "Failed to create request")?;

    let window = window().ok_or("No window")?;
    let resp_value = JsFuture::from(window.fetch_with_request(&request)).await?;
    let resp: web_sys::Response = resp_value.dyn_into().map_err(|_| "Failed to cast response")?;

    if !resp.ok() {
        return Err(format!("HTTP {}: Request failed", resp.status()).into());
    }

    let text = JsFuture::from(resp.text()?).await?;
    Ok(text)
}

#[wasm_bindgen]
pub fn generate_deploy_config(project_id: &str, project_name: &str, domain: &str) -> String {
    let config = serde_json::json!({
        "project_id": project_id,
        "project_name": project_name,
        "domain": domain,
        "api_url": "https://aristotle.harmonic.fun/api/v3",
        "cloudflare_pages": {
            "project_name": project_name,
            "output_dir": format!("./output-final_aristotle/{}_deployed", project_id),
            "use_site_dir": true,
            "commit_dirty": true
        },
        "deployment_steps": [
            "Download project from Aristotle API",
            "Extract and prepare deployment files",
            "Check for site/ subdirectory",
            "Deploy to Cloudflare Pages via wrangler",
            "Add custom domain if specified"
        ]
    });
    config.to_string()
}

#[wasm_bindgen]
pub fn get_deploy_instructions(project_id: &str, project_name: &str, domain: &str) -> String {
    format!(
        "To deploy project {} ({}) to Cloudflare Pages:\n\n\
         1. Install wrangler: npm install -g wrangler\n\
         2. Authenticate: wrangler login\n\
         3. Create project: wrangler pages project create {}\n\
         4. Deploy: wrangler pages deploy ./output-final_aristotle/{}_deployed --project-name {} --commit-dirty=true\n\
         5. Add domain: wrangler pages domain add {} --project-name {}\n\n\
         Note: Cloudflare wrangler v4.x does not support `pages domain add`. Add custom domains via Cloudflare Dashboard or API.",
        project_id, project_name, project_name, project_id, project_name, domain, project_name
    )
}

#[wasm_bindgen]
pub async fn deploy_project(project_id: &str, project_name: &str, domain: &str) -> Result<JsValue, JsValue> {
    log(&format!("Deploying project {} as {} with domain {}", project_id, project_name, domain));

    let config = generate_deploy_config(project_id, project_name, domain);

    let result = js_sys::Object::new();
    js_sys::Reflect::set(&result, &"success".into(), &true.into())?;
    js_sys::Reflect::set(&result, &"config".into(), &config.into())?;
    js_sys::Reflect::set(&result, &"instructions".into(), &get_deploy_instructions(project_id, project_name, domain).into())?;
    js_sys::Reflect::set(&result, &"project_id".into(), &project_id.into())?;
    js_sys::Reflect::set(&result, &"project_name".into(), &project_name.into())?;
    js_sys::Reflect::set(&result, &"domain".into(), &domain.into())?;

    Ok(result.into())
}

#[wasm_bindgen]
pub fn validate_project_id(project_id: &str) -> bool {
    let chars: Vec<char> = project_id.chars().collect();
    if chars.len() < 36 {
        return false;
    }
    chars.iter().take(8).all(|c| c.is_ascii_hexdigit()) && chars.get(8) == Some(&'-')
}

#[wasm_bindgen]
pub fn get_cloudflare_account_id() -> String {
    "0ceffbadd0a04623896f5317a1e40d94".to_string()
}

#[wasm_bindgen]
pub fn get_cloudflare_default_domain() -> String {
    "the-far-game.pages.dev".to_string()
}