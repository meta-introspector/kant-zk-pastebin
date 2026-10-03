// mesh.rs — relay-to-relay mesh networking for Kant pastebin
use crate::model::{MeshPeer, MeshMessage, MeshMessageKind, MeshPeerStatus, Identity, Avatar};
use crate::storage::Storage;
use actix_web::{web, HttpResponse, Result as ActixResult, http::header};
use reqwest::Client;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tokio::time::{interval, Duration};
use tracing::{info, warn, error, debug};

/// Configuration for mesh networking
#[derive(Clone, Debug)]
pub struct MeshConfig {
    pub local_relay_id: String,
    pub local_relay_url: String,
    pub peer_relays: Vec<String>,
    pub sync_interval_secs: u64,
    pub max_peers: usize,
    pub ping_interval_secs: u64,
}

impl Default for MeshConfig {
    fn default() -> Self {
        Self {
            local_relay_id: "relay-local".to_string(),
            local_relay_url: "http://127.0.0.1:8090".to_string(),
            peer_relays: Vec::new(),
            sync_interval_secs: 60,
            max_peers: 50,
            ping_interval_secs: 30,
        }
    }
}

/// Mesh networking state
pub struct MeshState {
    config: MeshConfig,
    peers: Arc<Mutex<HashMap<String, MeshPeer>>>,
    client: Client,
    storage: Arc<Storage>,
}

impl MeshState {
    pub fn new(config: MeshConfig, storage: Arc<Storage>) -> Self {
        let client = Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .expect("HTTP client");

        Self {
            config,
            peers: Arc::new(Mutex::new(HashMap::new())),
            client,
            storage,
        }
    }

    /// Save user identity to storage
    pub async fn save_identity(&self, identity: &Identity) -> anyhow::Result<()> {
        self.storage.save_identity(identity).await
    }

    /// Load user identity from storage
    pub async fn load_identity(&self, id: &str) -> Option<Identity> {
        self.storage.load_identity(id).await
    }

    /// List all identities in storage
    pub async fn list_identities(&self) -> Vec<Identity> {
        self.storage.list_identities().await
    }

    /// Save avatar to storage
    pub async fn save_avatar(&self, avatar: &Avatar) -> anyhow::Result<()> {
        self.storage.save_avatar(avatar).await
    }

    /// Load avatar from storage
    pub async fn load_avatar(&self, id: &str) -> Option<Avatar> {
        self.storage.load_avatar(id).await
    }

    /// List all avatars for a given owner
    pub async fn list_avatars(&self, owner: &str) -> Vec<Avatar> {
        self.storage.list_avatars(owner).await
    }

    /// Start the mesh networking background tasks
    pub fn start(self: Arc<Self>) {
        let state = self.clone();
        tokio::spawn(async move { state.peer_discovery_loop().await });

        let state = self.clone();
        tokio::spawn(async move { state.sync_loop().await });

        let state = self.clone();
        tokio::spawn(async move { state.ping_loop().await });
    }

    /// Peer discovery - connect to known relays and exchange peer lists
    async fn peer_discovery_loop(&self) {
        let mut interval = interval(Duration::from_secs(self.config.sync_interval_secs));
        loop {
            interval.tick().await;
            if let Err(e) = self.discover_peers().await {
                warn!("Peer discovery failed: {}", e);
            }
        }
    }

    /// Discover peers from known relays
    async fn discover_peers(&self) -> anyhow::Result<()> {
        let peer_relays = self.config.peer_relays.clone();
        for relay_url in &peer_relays {
            if let Ok(peers) = self.fetch_peers(relay_url).await {
                let mut local_peers = self.peers.lock().unwrap();
                for peer in peers {
                    local_peers.insert(peer.id.clone(), peer);
                }
            }
        }
        Ok(())
    }

    /// Fetch peer list from a relay
    async fn fetch_peers(&self, relay_url: &str) -> anyhow::Result<Vec<MeshPeer>> {
        let url = format!("{}/api/mesh/peers", relay_url.trim_end_matches('/'));
        let resp = self.client.get(&url).send().await?;
        let peers: Vec<MeshPeer> = resp.json().await?;
        Ok(peers)
    }

    /// Sync loop - periodically sync room state with peers
    async fn sync_loop(&self) {
        let mut interval = interval(Duration::from_secs(self.config.sync_interval_secs * 5));
        loop {
            interval.tick().await;
            if let Err(e) = self.sync_rooms().await {
                warn!("Room sync failed: {}", e);
            }
        }
    }

    /// Sync room state with all connected peers
    async fn sync_rooms(&self) -> anyhow::Result<()> {
        let peers: Vec<MeshPeer> = {
            let local_peers = self.peers.lock().unwrap();
            local_peers.values().cloned().collect()
        };

        for peer in peers {
            if peer.status != MeshPeerStatus::Online {
                continue;
            }
            self.sync_with_peer(&peer).await?;
        }
        Ok(())
    }

    /// Sync room state with a specific peer
    async fn sync_with_peer(&self, peer: &MeshPeer) -> anyhow::Result<()> {
        // In a full implementation, this would:
        // 1. Compare room state hashes
        // 2. Request missing messages
        // 3. Push new messages
        debug!("Syncing with peer: {}", peer.id);
        Ok(())
    }

    /// Ping loop - keep connections alive
    async fn ping_loop(&self) {
        let mut interval = interval(Duration::from_secs(self.config.ping_interval_secs));
        loop {
            interval.tick().await;
            self.ping_peers().await;
        }
    }

    /// Ping all known peers
    async fn ping_peers(&self) {
        let peers: Vec<MeshPeer> = {
            let local_peers = self.peers.lock().unwrap();
            local_peers.values().cloned().collect()
        };

        for peer in peers {
            if let Err(e) = self.ping_peer(&peer).await {
                warn!("Ping to {} failed: {}", peer.id, e);
                self.mark_peer_offline(&peer.id).await;
            }
        }
    }

    /// Ping a specific peer
    async fn ping_peer(&self, peer: &MeshPeer) -> anyhow::Result<()> {
        let url = format!("{}/api/mesh/ping", peer.relay.trim_end_matches('/'));
        let msg = MeshMessage {
            id: uuid::Uuid::new_v4().to_string(),
            from: self.config.local_relay_id.clone(),
            to: Some(peer.id.clone()),
            kind: MeshMessageKind::RelayPing,
            payload: serde_json::to_string(&self.config.local_relay_id)?,
            timestamp: std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)?.as_secs(),
        };
        let resp = self.client.post(&url).json(&msg).send().await?;
        resp.error_for_status()?;
        Ok(())
    }

    /// Mark a peer as offline
    async fn mark_peer_offline(&self, peer_id: &str) {
        let mut peers = self.peers.lock().unwrap();
        if let Some(peer) = peers.get_mut(peer_id) {
            peer.status = MeshPeerStatus::Offline;
        }
    }

    /// Register a new peer (from incoming connection)
    pub fn register_peer(&self, peer: MeshPeer) {
        let mut peers = self.peers.lock().unwrap();
        if peers.len() < self.config.max_peers {
            peers.insert(peer.id.clone(), peer);
        }
    }

    /// Get all known peers
    pub fn get_peers(&self) -> Vec<MeshPeer> {
        let peers = self.peers.lock().unwrap();
        peers.values().cloned().collect()
    }

    /// Handle incoming mesh message
    pub async fn handle_message(&self, msg: MeshMessage) -> anyhow::Result<()> {
        match msg.kind {
            MeshMessageKind::IdentityAnnounce => {
                // Parse identity from payload
                let identity: Identity = serde_json::from_str(&msg.payload)?;
                self.storage.save_identity(&identity).await?;
                info!("Received identity announcement: {}", identity.id);
            }
            MeshMessageKind::RoomSync => {
                // Sync room state
                debug!("Room sync message from {}", msg.from);
            }
            MeshMessageKind::PasteSync => {
                // Sync paste data
                debug!("Paste sync message from {}", msg.from);
            }
            MeshMessageKind::AvatarSync => {
                // Sync avatar data
                let avatar: Avatar = serde_json::from_str(&msg.payload)?;
                self.storage.save_avatar(&avatar).await?;
                info!("Received avatar sync: {}", avatar.id);
            }
            MeshMessageKind::RelayPing => {
                // Just respond with pong
                info!("Ping from {}", msg.from);
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    use tempfile::TempDir;

    /// A `Storage` in a directory of this test's own.
    ///
    /// `Storage::new(None)` falls back to `$HOME/.kant-pastebin`, so every test
    /// using it shared one directory and the same `ident-1`/`avatar-1` ids:
    /// `test_mesh_state_proxy_methods` passed alone and failed beside the
    /// others, and wrote into the live service's data directory. Each caller
    /// keeps its `TempDir` alive, since removing it early would defeat the
    /// point. For the service user the fallback is /var/empty, so a test using
    /// it would write where the service cannot and assert against whatever
    /// was already there.
    fn storage_in(dir: &TempDir) -> Arc<Storage> {
        Arc::new(Storage::new(Some(dir.path().to_string_lossy().to_string())))
    }

    fn sample_identity() -> Identity {
        Identity {
            id: "ident-1".to_string(),
            name: "testuser".to_string(),
            display_name: Some("Test User".to_string()),
            avatar_id: Some("avatar-1".to_string()),
            bio: Some("A test bio".to_string()),
            relays: vec!["http://relay.local".to_string()],
            created: 0,
            updated: 0,
        }
    }

    fn sample_avatar() -> Avatar {
        Avatar {
            id: "avatar-1".to_string(),
            owner: "ident-1".to_string(),
            data_url: Some("data:image/png;base64,abcd".to_string()),
            ipfs_cid: None,
            mime_type: "image/png".to_string(),
            size_bytes: 1234,
            created: 0,
        }
    }

    /// `MeshState`'s methods are async but the tests are not `#[tokio::test]`:
    /// the crate has tokio in [dependencies] for the mesh's own use, and a
    /// half-registered macro is a test that silently does not run.
    /// `MeshState`'s methods are async but the tests are not `#[tokio::test]`:
    /// the crate has tokio in [dependencies] for the mesh's own use, and a
    /// half-registered macro is a test that silently does not run.
    fn run_async<F, R>(fut: F) -> R
    where
        F: std::future::Future<Output = R>,
    {
        tokio::runtime::Runtime::new().unwrap().block_on(fut)
    }

    /// The proxy methods on MeshState delegate to the wrapped Storage.
    #[test]
    fn test_mesh_state_proxy_methods() {
        run_async(async {
            let dir = TempDir::new().expect("temp dir");
            let state = MeshState::new(MeshConfig::default(), storage_in(&dir));

            let identity = sample_identity();
            state.save_identity(&identity).await.expect("save identity");

            let loaded = state.load_identity("ident-1").await;
            assert_eq!(loaded, Some(identity.clone()));

            let list = state.list_identities().await;
            assert_eq!(list.len(), 1);
            assert_eq!(list[0].id, "ident-1");

            let avatar = sample_avatar();
            state.save_avatar(&avatar).await.expect("save avatar");

            let loaded_avatar = state.load_avatar("avatar-1").await;
            assert_eq!(loaded_avatar, Some(avatar.clone()));

            let avatars = state.list_avatars("ident-1").await;
            assert_eq!(avatars.len(), 1);
            assert_eq!(avatars[0].owner, "ident-1");
        });
    }

    /// Two MeshState instances sharing one Storage see each other's writes.
    #[test]
    fn test_two_mesh_state_instances_shared_storage() {
        run_async(async {
            let dir = TempDir::new().expect("temp dir");
            let storage = storage_in(&dir);
            let state_a = MeshState::new(MeshConfig::default(), storage.clone());
            let state_b = MeshState::new(MeshConfig::default(), storage);

            let identity = sample_identity();
            state_a.save_identity(&identity).await.expect("save via state_a");

            // state_b can read what state_a saved (shared persistence).
            let loaded = state_b.load_identity("ident-1").await;
            assert_eq!(loaded, Some(identity));
        });
    }

    /// Two MeshState instances with separate Storage stay isolated.
    #[test]
    fn test_two_mesh_state_instances_isolated_storage() {
        run_async(async {
            let dir_a = TempDir::new().expect("temp dir a");
            let dir_b = TempDir::new().expect("temp dir b");
            let state_a = MeshState::new(MeshConfig::default(), storage_in(&dir_a));
            let state_b = MeshState::new(MeshConfig::default(), storage_in(&dir_b));

            state_a.save_identity(&sample_identity()).await.expect("save a");
            assert!(
                state_b.load_identity("ident-1").await.is_none(),
                "isolated storage must not see the other state's writes"
            );
        });
    }

    /// list_avatars filters by owner rather than returning everything.
    #[test]
    fn test_mesh_state_list_avatars_filter() {
        run_async(async {
            let dir = TempDir::new().expect("temp dir");
            let state = MeshState::new(MeshConfig::default(), storage_in(&dir));

            let owner1 = sample_avatar();
            let mut owner2 = sample_avatar();
            owner2.id = "avatar-2".to_string();
            owner2.owner = "ident-2".to_string();

            state.save_avatar(&owner1).await.expect("save avatar 1");
            state.save_avatar(&owner2).await.expect("save avatar 2");

            let for_owner1 = state.list_avatars("ident-1").await;
            assert_eq!(for_owner1.len(), 1);
            assert_eq!(for_owner1[0].id, "avatar-1");

            let for_owner2 = state.list_avatars("ident-2").await;
            assert_eq!(for_owner2.len(), 1);
            assert_eq!(for_owner2[0].id, "avatar-2");
        });
    }
}

/// API handlers for mesh networking
pub mod handlers {
    use super::*;
    use actix_web::{web, HttpResponse, Result as ActixResult};
    use actix_web::error::ErrorInternalServerError;

    /// GET /api/mesh/peers - List all known mesh peers
    pub async fn list_peers(state: web::Data<Arc<MeshState>>) -> ActixResult<HttpResponse> {
        let peers = state.get_peers();
        Ok(HttpResponse::Ok().json(peers))
    }

    /// POST /api/mesh/ping - Receive a ping from another relay
    pub async fn receive_ping(
        state: web::Data<Arc<MeshState>>,
        msg: web::Json<MeshMessage>,
    ) -> ActixResult<HttpResponse> {
        state
            .handle_message(msg.into_inner())
            .await
            .map_err(ErrorInternalServerError)?;
        Ok(HttpResponse::Ok().json(serde_json::json!({ "ok": true })))
    }

    /// POST /api/mesh/message - Receive a mesh message
    pub async fn receive_message(
        state: web::Data<Arc<MeshState>>,
        msg: web::Json<MeshMessage>,
    ) -> ActixResult<HttpResponse> {
        state
            .handle_message(msg.into_inner())
            .await
            .map_err(ErrorInternalServerError)?;
        Ok(HttpResponse::Ok().json(serde_json::json!({ "ok": true })))
    }

    /// POST /api/mesh/announce - Announce this relay's identity
    pub async fn announce(
        state: web::Data<Arc<MeshState>>,
        identity: web::Json<Identity>,
    ) -> ActixResult<HttpResponse> {
        let identity = identity.into_inner();
        state
            .storage
            .save_identity(&identity)
            .await
            .map_err(ErrorInternalServerError)?;
        Ok(HttpResponse::Ok().json(serde_json::json!({ "ok": true })))
    }
}