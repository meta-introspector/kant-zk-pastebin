// Storage - Load/save pastes from UUCP/IPFS/consumer service
use std::env;
use std::fs;

pub fn load_content(id: &str) -> Option<String> {
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let filename = format!("{}/{}.txt", uucp_dir, id);

    if let Ok(content) = fs::read_to_string(&filename) {
        return Some(content);
    }

    None
}

pub fn save_content(id: &str, content: &str) -> Result<(), std::io::Error> {
    let uucp_dir = env::var("UUCP_SPOOL").unwrap_or_else(|_| "/var/spool/uucp".to_string());
    let filename = format!("{}/{}.txt", uucp_dir, id);

    fs::write(&filename, content)?;
    Ok(())
}

fn load_from_ipfs(id: &str) -> Option<String> {
    None
}

fn save_to_ipfs(_content: &str) -> Option<String> {
    None
}
