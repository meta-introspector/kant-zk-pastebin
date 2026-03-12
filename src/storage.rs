// Storage - Load/save pastes from UUCP/IPFS/Kafka-like API
use std::fs;
use std::env;

pub fn load_content(id: &str) -> Option<String> {
    if let Some(content) = load_from_api(id) {
        return Some(content);
    }
    
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let filename = format!("{}/{}.txt", uucp_dir, id);
    
    if let Ok(content) = fs::read_to_string(&filename) {
        return Some(content);
    }
    
    load_from_ipfs(id)
}

pub fn save_content(id: &str, content: &str) -> Result<(), std::io::Error> {
    save_to_api(id, content);
    
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let filename = format!("{}/{}.txt", uucp_dir, id);
    
    fs::write(&filename, content)?;
    save_to_ipfs(content);
    Ok(())
}

fn load_from_api(id: &str) -> Option<String> {
    let api_url = env::var("KAFKA_API_URL").ok()?;
    let url = format!("{}/get/{}", api_url, id);
    reqwest::blocking::get(&url).ok()?.text().ok()
}

fn save_to_api(id: &str, content: &str) {
    if let Ok(api_url) = env::var("KAFKA_API_URL") {
        let url = format!("{}/put/{}", api_url, id);
        let _ = reqwest::blocking::Client::new()
            .post(&url)
            .body(content.to_string())
            .send();
    }
}

fn load_from_ipfs(id: &str) -> Option<String> {
    None
}

fn save_to_ipfs(content: &str) -> Option<String> {
    None
}
