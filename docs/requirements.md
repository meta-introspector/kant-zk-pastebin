# Pastebin Hard Requirements

## 1. No root
All services must run as an unprivileged user (`kant`). No `sudo`, no root-owned paths, no setuid.

## 2. No homedirs
No `$HOME`, no `~/.ipfs`, no `~/.config`, no per-user dotfiles. All state under `/mnt/data1` or nix store.

## 3. Only nix build
Builds only via `nix build`. No `cargo build`, no `target/release`, no manual compilation artifacts.

## 4. Only systemd via system-manager
Service management only through `system-manager` (nix-based). No `systemctl start/stop` by hand.

## 5. Git locally, nora packages
Source in local git branches (`git+file://`). Dependencies via nora package registry where applicable.

## 6. No shelling out, no syscalls
No `std::process::Command`, no `std::process::Command::new`, no shelling out to `ipfs`, `curl`, etc. All operations through native Rust libraries.

## 7. No inline code
No large code blocks pasted into handlers. Logic split into proper modules (`handlers/`, `storage/`, `ipfs/`, etc.).

## 8. Deploy path
`./deploy.sh` → nix build → system-manager activate → systemd restart of `kant-pastebin.service`.

## Audit
- `src/ipfs.rs`: `dirs_next::home_dir()` → violates #2 (homedir fallback).
- `src/ipfs.rs`: `IpfsCliStore::add` shells out to `ipfs` CLI → violates #6.
- `src/mcp_server.rs`: `reqwest::blocking::Client` → external HTTP call, not pure Rust → violates #6.
- `src/storage.rs`: `KAFKA_API_URL` env var → violates #6 (delegating to external consumer).
- `src/handlers.rs`: inline large `upload_file` handler → violates #7.
- Service runs as `kant` → OK for #1.
- IPFS repo should be `/mnt/data1/ipfs` or `/mnt/data1/spool/uucp/pastebin/.ipfs`, never `~/.ipfs`.
