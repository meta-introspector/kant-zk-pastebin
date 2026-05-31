---
name: multi-root-scanner
description: Walk multiple filesystem roots (org files, markdown, git repos) and import them as pastes into the Kant Pastebin. Use when: (1) Importing a directory of `.org` files as pastes, (2) Scanning multiple source directories, (3) Setting up a recurring import cron job, (4) Reindexing after content changes.
---

# Multi-Root Scanner

## Architecture

The multi-root scanner is a config-driven CLI tool that:

1. Reads a config file listing source roots
2. Walks each root for `.org` files
3. Extracts title from `#+TITLE:` or falls back to filename
4. Creates/stores a paste from each file
5. Records the `root` origin in the `PasteIndex`

## Configuration

Config file: `scanner.toml` (default) or custom path

```toml
[[roots]]
path = "/mnt/data1/time-2026/05-may/14"
label = "2026-05-14"
recursive = true
file_pattern = "*.org"
title_regex = "^#\\+TITLE:\\s*(.+)$"

[[roots]]
path = "/mnt/data1/time-2026/05-may/25"
label = "2026-05-25"
recursive = true
file_pattern = "*.org"
title_regex = "^#\\+TITLE:\\s*(.+)$"
```

## Usage

```bash
# Import from all configured roots
cargo run --bin multi-reindex -- --config scanner.toml

# Import from specific roots only
cargo run --bin multi-reindex -- --root /path/to/org-dir --label my-blog

# List what would be imported (dry run)
cargo run --bin multi-reindex -- --config scanner.toml --dry-run

# Reindex (import only new/changed files)
cargo run --bin multi-reindex -- --config scanner.toml --reindex
```

## PasteIndex Fields

| Field | Description |
|---|---|
| `id` | Paste UUID |
| `title` | Extracted from `#+TITLE:` or filename |
| `content` | Full file content |
| `created_at` | File modification time |
| `tags` | Auto-tagged from content via `tagging.rs` |
| `root` | Origin root label (e.g. "2026-05-25") |

## Nix Integration

```bash
# Run via Nix
nix run .#multi-reindex -- --config /etc/pastebin/scanner.toml

# Or as a periodic systemd timer
nix build .#multi-reindex
```
