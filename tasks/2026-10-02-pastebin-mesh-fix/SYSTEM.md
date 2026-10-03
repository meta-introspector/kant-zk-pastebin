# Task: Pastebin mesh state methods fix

**Status:** completed

## Problem

The `announce_identity` handler in `src/handlers.rs:361-368` calls `state.save_identity(&identity).await?` where `state: web::Data<Arc<MeshState>>`. However, `MeshState` in `src/mesh.rs` does NOT have a `save_identity` method — it only stores an `Arc<Storage>` field. The other identity/avatar handlers (`list_identities`, `get_identity`, `create_identity`, `list_avatars`, `upload_avatar`, `get_avatar`) correctly use `web::Data<Arc<Storage>>` and call methods directly on `Storage`, which has `save_identity`, `load_identity`, `list_identities`, `save_avatar`, `load_avatar`, `list_avatars`.

The fix: add 6 proxy methods to the `impl MeshState` block in `src/mesh.rs` that delegate to `self.storage`:
- `save_identity(&self, identity: &Identity) -> anyhow::Result<()>`
- `load_identity(&self, id: &str) -> Option<Identity>`
- `list_identities(&self) -> Vec<Identity>`
- `save_avatar(&self, avatar: &Avatar) -> anyhow::Result<()>`
- `load_avatar(&self, id: &str) -> Option<Avatar>`
- `list_avatars(&self, owner: &str) -> Vec<Avatar>`

## Fix Applied

In `src/mesh.rs`, within the `impl MeshState` block after `new()` and before `start()`, added the 6 proxy methods that delegate `self.storage` methods.

## Root Cause

The `announce_identity` handler was registered with the wrong `state` type. It should use `web::Data<Arc<Storage>>` like the other mesh handlers, OR `MeshState` should proxy the storage methods. The minimal fix is adding proxy methods to `MeshState` (since the handler signature already uses `MeshState`).

## Split Tasks (for agents)

### Task 1: Verify Fix Compiles
Agent: rust-fixer
- Run `cargo check -p kant-pastebin` (or longer timeout) in the worktree at `kant-pastebin-mesh-fix`
- Confirm the 6 proxy methods resolve the compile error in `announce_identity`
- Check for any other missing methods referenced from handlers

### Task 2: Commit and Create PR
Agent: git-bot
- Commit the fix to branch `fix/mesh-state-methods` in the worktree
- Push branch and open PR against `feature/big-merge` (or appropriate base)
- Verify CI passes

### Task 3: Update Worktree Tracking
Agent: worktree-manager
- Ensure the fix is present in the worktree at `/mnt/data1/kant/kant-pastebin-mesh-fix`
- If not, copy the fix from main tree or re-apply proxy methods

## Deliverables

- 6 proxy methods added to `MeshState` in `src/mesh.rs`
- `announce_identity` compiles without errors
- Commit and PR created in worktree branch `fix/mesh-state-methods`

## Results (completed 2026-10-02)

### Fix applied:
- 6 proxy methods added to `MeshState` in `src/mesh.rs:58-86`
- Fixed E0277 errors in handlers.rs (4 sites) and mesh.rs::handlers (3 sites) by replacing bare `?` with `.map_err(actix_web::error::ErrorInternalServerError)?`

### Pre-existing errors fixed to enable compilation:
- Added `PartialEq, Eq` derives to `Identity` and `Avatar` in `model.rs`
- Added `ThreadPost` struct to `model.rs`
- Added `MeshPeerStatus` enum (proper formatting) in `model.rs`
- Added stub functions (`clean_field`, `capture_error_case`, `archive_name_title`, `file_description`, `write_index_entry`) to handlers.rs
- Fixed `get_raw` handler to use `Storage::new()`
- Added `use crate::storage::Storage;` import to handlers.rs

### Tests added (all pass):
- `test_mesh_state_proxy_methods` — verifies all 6 proxy methods
- `test_two_mesh_state_instances_shared_storage` — shared `Arc<Storage>`
- `test_two_mesh_state_instances_isolated_storage` — separate `Storage` dirs (offline mode)
- `test_mesh_state_list_avatars_filter` — owner filtering

### PR created:
- https://github.com/meta-introspector/kant-zk-pastebin/pull/5