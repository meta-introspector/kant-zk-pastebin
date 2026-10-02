// Storage - Load/save pastes from UUCP/IPFS/consumer service
use crate::model::{Avatar, Identity};
use std::env;
use std::fs;
use std::path::PathBuf;
use tracing::{info, warn};

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

/// On-disk store for mesh identities and avatars.
///
/// Ported from the `wip` commit (150437b6), which removed the UUCP
/// free functions above; here both coexist because the pre-wip tree is
/// what mesh.rs is being re-applied onto.
pub struct Storage {
    pub data_dir: PathBuf,
}

impl Storage {
    pub fn new(data_dir: Option<String>) -> Self {
        let dir = data_dir.map(PathBuf::from).unwrap_or_else(|| {
            // The service runs as `kant`, whose HOME is /var/empty and is
            // not writable, so this has to be able to land somewhere else
            // rather than take the whole server down with it.
            match env::var("HOME") {
                Ok(h) if !h.is_empty() && h != "/var/empty" => PathBuf::from(h).join(".kant-pastebin"),
                _ => PathBuf::from("/var/lib/kant-pastebin"),
            }
        });
        // Never panic here. This runs during startup, before the listener
        // exists, so a failure to create the directory would otherwise
        // crash-loop the service instead of degrading to "mesh state is
        // not persisted".
        if let Err(e) = fs::create_dir_all(&dir) {
            warn!(
                "mesh storage dir {} is unavailable ({}); identities and avatars will not persist",
                dir.display(),
                e
            );
        }
        Self { data_dir: dir }
    }

    /// Save user identity to local storage
    pub async fn save_identity(&self, identity: &Identity) -> anyhow::Result<()> {
        let identity_dir = self.data_dir.join("identities");
        fs::create_dir_all(&identity_dir)?;
        let path = identity_dir.join(format!("{}.json", identity.id));
        let json = serde_json::to_string_pretty(identity)?;
        fs::write(&path, json)?;
        info!("Saved identity: {}", identity.id);
        Ok(())
    }

    /// Load user identity from local storage
    pub async fn load_identity(&self, id: &str) -> Option<Identity> {
        let path = self.data_dir.join("identities").join(format!("{}.json", id));
        let json = fs::read_to_string(&path).ok()?;
        serde_json::from_str::<Identity>(&json).ok()
    }

    /// List all identities in local storage
    pub async fn list_identities(&self) -> Vec<Identity> {
        let mut identities = Vec::new();
        let identity_dir = self.data_dir.join("identities");
        if !identity_dir.exists() {
            return identities;
        }
        let entries = match fs::read_dir(&identity_dir) {
            Ok(entries) => entries,
            Err(e) => {
                warn!("Cannot read identities dir: {}", e);
                return identities;
            }
        };
        for entry in entries {
            if let Ok(entry) = entry {
                if let Some(path) = entry.path().extension() {
                    if path == "json" {
                        if let Ok(json) = fs::read_to_string(entry.path()) {
                            if let Ok(identity) = serde_json::from_str::<Identity>(&json) {
                                identities.push(identity);
                            }
                        }
                    }
                }
            }
        }
        identities
    }

    /// Save avatar to local storage
    pub async fn save_avatar(&self, avatar: &Avatar) -> anyhow::Result<()> {
        let avatar_dir = self.data_dir.join("avatars");
        fs::create_dir_all(&avatar_dir)?;
        let path = avatar_dir.join(format!("{}.json", avatar.id));
        let json = serde_json::to_string_pretty(avatar)?;
        fs::write(&path, json)?;
        info!("Saved avatar: {}", avatar.id);
        Ok(())
    }

    /// Load avatar from local storage
    pub async fn load_avatar(&self, id: &str) -> Option<Avatar> {
        let path = self.data_dir.join("avatars").join(format!("{}.json", id));
        let json = fs::read_to_string(&path).ok()?;
        serde_json::from_str::<Avatar>(&json).ok()
    }

    /// List all avatars for a given owner
    pub async fn list_avatars(&self, owner: &str) -> Vec<Avatar> {
        let mut avatars = Vec::new();
        let avatar_dir = self.data_dir.join("avatars");
        if !avatar_dir.exists() {
            return avatars;
        }
        let entries = match fs::read_dir(&avatar_dir) {
            Ok(entries) => entries,
            Err(e) => {
                warn!("Cannot read avatars dir: {}", e);
                return avatars;
            }
        };
        for entry in entries {
            if let Ok(entry) = entry {
                if let Some(path) = entry.path().extension() {
                    if path == "json" {
                        if let Ok(json) = fs::read_to_string(entry.path()) {
                            if let Ok(avatar) = serde_json::from_str::<Avatar>(&json) {
                                if avatar.owner == owner {
                                    avatars.push(avatar);
                                }
                            }
                        }
                    }
                }
            }
        }
        avatars
    }
}

fn load_from_ipfs(id: &str) -> Option<String> {
    None
}

fn save_to_ipfs(_content: &str) -> Option<String> {
    None
}
