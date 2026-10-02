# Mesh Networking Enhancement for Kant Pastebin

This document describes the implementation of mesh networking capabilities for the Kant pastebin system, allowing relays to communicate with each other and share identities, avatars, and paste data across a peer-to-peer network.

## Overview

The Kant pastebin system now supports:
- **Relay-to-relay mesh networking** - Relays can discover and communicate with each other
- **Identity management** - Users can create and share profiles across relays
- **Avatar support** - Users can upload and share avatars (stored locally or via IPFS)
- **Automatic synchronization** - Room state and user data sync between connected relays
- **Peer discovery** - Relays can discover peers through known relay lists

## Components Added

### 1. Data Models (`src/model.rs`)

New data structures:
- `Avatar` - User avatar with local storage (data URL) or IPFS CID options
- `Identity` - User profile with name, display name, avatar reference, bio, and known relays
- `MeshPeer` - Represents a peer in the mesh network with identity and status
- `MeshMessage` - Messages exchanged between relays (identity announcements, room syncs, etc.)
- `MeshMessageKind` - Types of mesh messages (IdentityAnnounce, RoomSync, PasteSync, AvatarSync, RelayPing)

### 2. Mesh Networking (`src/mesh.rs`)

Core mesh networking implementation:
- `MeshConfig` - Configuration for mesh networking (peer lists, intervals, limits)
- `MeshState` - Manages peer discovery, synchronization, and messaging
  - Peer discovery loop - Periodically checks known relays for peer lists
  - Sync loop - Periodically synchronizes room state with peers
  - Ping loop - Keeps connections alive with periodic pings
  - Message handling - Processes incoming mesh messages by type
- API handlers for mesh operations:
  - `list_mesh_peers` - GET /api/mesh/peers
  - `receive_mesh_ping` - POST /api/mesh/ping
  - `announce_identity` - POST /api/mesh/announce
  - Plus identity and avatar management endpoints

### 3. Storage Enhancements (`src/storage.rs`)

Extended to handle:
- Identity persistence (JSON files in ~/.kant-pastebin/identities/)
- Avatar persistence (JSON files in ~/.kant-pastebin/avatars/)
- Methods to save/load/list identities and avatars

### 4. API Endpoints

Added to `src/main.rs`:

**Mesh Networking:**
- `GET /api/mesh/peers` - List all known mesh peers
- `POST /api/mesh/ping` - Receive ping from another relay
- `POST /api/mesh/announce` - Announce this relay's identity

**Identity Management:**
- `GET /api/identities` - List all saved identities
- `GET /api/identities/{id}` - Get a specific identity
- `POST /api/identities` - Create a new identity

**Avatar Management:**
- `GET /api/avatars/{owner}` - List avatars for a specific owner
- `POST /api/avatars` - Upload a new avatar
- `GET /api/avatars/{id}` - Get a specific avatar

### 5. Integration

- Updated `src/lib.rs` to include the `mesh` module
- Updated `src/main.rs` to import the mesh module and register all new API routes

## Usage

### Running a Mesh-Enabled Relay

To run a relay that participates in mesh networking:

```bash
# Start the Kant pastebin server
./target/release/kant-pastebin

# Or with specific configuration
UUCP_SPOOL=/mnt/data1/spool/uucp/pastebin \
TILES_DIR=/path/to/tiles \
./target/release/kant-pastebin
```

For mesh networking, configure peer relays via environment variables or modify the MeshConfig defaults.

### Peer Discovery

Relays automatically discover peers by:
1. Checking the list of known relays in `MeshConfig.peer_relays`
2. Periodically querying each known relay for its peer list
3. Adding discovered peers to the local peer mesh

### Identity and Avatar Management

Users can manage their identities and avatars through the API:

```bash
# Create an identity
curl -X POST http://localhost:8090/api/identities \
  -H "Content-Type: application/json" \
  -d '{
    "name": "alice",
    "display_name": "Alice Engineer",
    "bio": "Kant protocol enthusiast",
    "relays": ["http://relay1.example.com:8090", "http://relay2.example.com:8090"]
  }'

# Upload an avatar (base64 encoded image)
curl -X POST http://localhost:8090/api/avatars \
  -H "Content-Type: application/json" \
  -d '{
    "owner": "alice",
    "data_url": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
    "mime_type": "image/png",
    "size_bytes": 68
  }'
```

## Future Enhancements

1. **Automatic peer relay configuration** - Allow relays to learn about new peers from existing ones
2. **Selective synchronization** - Allow users to choose which data to sync (public vs private)
3. **Conflict resolution** - Handle concurrent updates to the same identity/avatar
4. **Message encryption** - End-to-end encryption for sensitive mesh messages
5. **Performance optimizations** - Batch messaging and compression for large syncs
6. **WebSocket mesh connections** - Replace HTTP polling with persistent WebSocket connections for lower latency

## Security Considerations

- **Identity verification** - Currently relies on trust; future versions could add cryptographic verification
- **Rate limiting** - Mesh messages should be rate-limited to prevent abuse
- **Data validation** - All incoming data should be validated for size and content
- **Access control** - Consider implementing ACLs for sensitive operations

## Implementation Notes

The mesh networking is designed to be:
- **Eventually consistent** - Peers will converge to the same state over time
- **Fault tolerant** - Handles temporary network partitions gracefully
- **Scalable** - Designed to work with dozens to hundreds of peers
- **Backward compatible** - Existing relays without mesh capabilities continue to work normally

The implementation follows the Kant protocol principles:
- Minimal trust assumptions - Relays don't need to trust each other's data
- Self-certifying data - Identities and avatars can be verified by recipients
- Efficient synchronization - Only transmits changes when possible