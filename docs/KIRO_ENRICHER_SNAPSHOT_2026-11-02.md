# Kiro parquet snapshot → task-enricher (2026-11-02)

Cross-repo record of this session: wiring **all** agent chat stores into the
task-enricher, building the kiro-cli parquet → JSONL snapshot, and (same
session) a zkperf witness ringbuffer fix. The code lives in the enricher repo
and in `pastebin-clean/zkperf`; this file is the record.

- Enricher repo: `/home/mdupont/dotagents/task-enricher`
  → resolves to `/mnt/data1/time-2026/05-may/31/n0x-pi/.dotagents`
  (the tree `task-enricher-gui.service` builds from)
- The diverged split copy `/mnt/data1/dotagents-split/task-enricher`
  (not a git repo) was left untouched.

## 1. Goal

The enricher's agent-log phase reads chat stores from its `log_dirs`; the
kiro-cli store was never among them. Decision: pull kiro in **via a parquet
snapshot** (kiro is only used sometimes — a snapshot is enough, re-runnable),
then find all GPU work done there.

## 2. task-enricher changes

### 2.1 New default log dirs (`src/config.rs` `for_home`, mirrored in
`plan_links.rs` `LinksConfig::default`)

| Dir | Why |
|---|---|
| `~/.claude/projects` | Claude Code session JSONL lives one level deeper than `.claude` — the old 2-level walk could never reach it |
| `~/.gemini/tmp` | Gemini CLI per-session chat JSON under the hash dirs |
| `/mnt/data1/.emacs.d.kiro/chats` | kiro/chatgpt-shell emacs conversation archives (host-wide, not under `$HOME`; `/mnt/data1` hardcoding follows the existing `repos` precedent) |
| `/mnt/data1/.emacs.d.kiro/kiro.el/chats` | kiro emacs chat archives |
| `~/.local/share/kiro-chat-snapshot` | the parquet export of §3 (added 2026-11-02) |

### 2.2 Bounded deep walk (`src/plan_links.rs` `collect_log_files`)

- **Was:** fixed 2 levels, `.log`/`.jsonl` only.
- **Now:** recursive, `MAX_LOG_DEPTH = 6`, `MAX_LOG_FILES = 2048` per dir,
  extensions `.log`/`.jsonl`/`.json` (kiro chats are one whole conversation
  per `.json`/`.jsonl`), symlinked dirs skipped so link loops can't steer it.
- **Rails kept:** 32 MB size cap, 64 KB head read, ≥ 2 distinct task keywords
  to count, `enrich-*.log` exclusion, global top 8 ranked by score with mtime
  as tiebreak.

### 2.3 Candidate pool 25 → 1024 (2026-11-02)

`log_files.truncate(25)` made an archive dir's history unreachable: with 866
snapshot conversations, the newest-25 cutoff landed on **2026-03-18**, so 791
files — every Dec-2025/Jan-2026 cargo2nix conversation among them — were
never even scored. Raised to **1024** (all 866 fit); cost bound is
1024 × 64 KB head ≈ 64 MB of reads per dir worst case. Comment in
`plan_links.rs` records the rationale.

### 2.4 Verification

- `cargo test --release -p task-enricher` → **exit 0, 99 passed / 0 failed**
  (incl. `agent_logs_reach_deep_json_chats_and_pi_sessions`, which scores a
  4-levels-down `.json` chat through the real `find_agent_logs`). The
  pre-existing unused-import/variable warnings are unchanged.
- Release binary `/home/mdupont/dotagents/target/release/task-enricher` is
  newer than all touched sources. **Restart `task-enricher-gui.service` if it
  caches the binary**; otherwise the next enrich run picks it up.
- `README.md` updated: log-dir table, file-format/walk section, pool note,
  snapshot refresh section, test count 82 → 99.

## 3. Kiro snapshot pipeline

### 3.1 Source

- `/mnt/data1/time-2026/03-march/19/kiro-chat-backup/conversations_v2_chunk_*.parquet`
  — 9 chunks, ~388 MB; schema `key, conversation_id, value (JSON string),
  created_at, updated_at`.
- Produced from `~/.local/share/kiro-cli/data.sqlite3` by `export_chats.py`
  (`SOP_Export_Kiro_Chats.md` / SOP-ERDFA-003).

### 3.2 Export script — `scripts/kiro_chat_export.py`

- Needs only `pyarrow` (25.0.1 present; no pandas).
- Output: `~/.local/share/kiro-chat-snapshot/<created_at>_<conversation_id>.jsonl`
  — **866 conversations, ~82 MB**, largest file 265 KB (far under the 32 MB
  enricher cap).
- Line 1 = metadata (date, cwd, conversation id, summary); line 2+ = one
  `{"role": …, "text": …}` per turn. File **mtime = conversation
  `updated_at`** (drives the newest-first pool and dates the timeline
  zipper); the `YYYY-MM-DD` filename prefix does the same for the axis.
- Refresh:

  ```bash
  python3 scripts/kiro_chat_export.py \
      [--src /mnt/data1/time-2026/03-march/19/kiro-chat-backup] \
      [--out ~/.local/share/kiro-chat-snapshot]
  ```

### 3.3 Extraction quirks (why v1 failed)

- v1 kept **0 of 8,920** assistant messages: assistant text lives in
  `Response.content` / `ToolUse.content` / `tool_uses` (names + args), not in
  any top-level message field.
- `ToolUseResults` carries tool output — the **78 MB bulk** of the raw data —
  so it is bounded at export: 2,000 chars per block, 8,000 per result set,
  100,000 per turn.
- After the fix: 3.4 M chars of assistant+tool text in chunk 0 alone; output
  went 15 MB → 82 MB (content, not padding; largest file still 265 KB).

## 4. End-to-end verification (2026-11-02)

`task-enricher enrich --dir <task> --focus agent-logs`:

| run | task keywords | result |
|---|---|---|
| A | generic (`kiro, snapshot, conversation, work, check…`) | top 8 = pi sessions only; snapshot files scored 12 but lost the mtime tiebreak to newer pi sessions — by design (global top 8) |
| B | distinctive (`cargo2nix, split-decls, vendor, workspace`) | **7 kiro snapshot conversations, 2025-12-27 → 2026-01-12**, plus a Gemini session from the deep walk |

Run B's hits all predate the old newest-25 cutoff (2026-03-18) → proves both
the pool fix and the snapshot wiring. An earlier run proved the emacs kiro
archives (`kiro.el/chats/…json`, 9 hits, 980 KB).

Context: **865 of 866** snapshot files score ≥ 2 against a generic keyword
set — generic words match everything, so to surface *old* evidence the task's
`SYSTEM.md` must name distinctive terms.

## 5. Known limits

- The kiro-cli **SQLite store is not read** (`~/.local/share/kiro-cli/data.sqlite3`
  is a database, no `log_dirs` entry can reach it) — the parquet export
  pipeline covers it; a built-in reader would be a separate feature.
- Snapshot refreshes are manual (re-run the script).
- `funes` is not on PATH (warning during runs); the postgres locate wait makes
  a `--focus agent-logs` run take ~1.5–2.5 min wall (≈1 s CPU).
- Nothing was committed this session — both repos are left with the changes.

## 6. Same session: zkperf witness ringbuffer fix

File: `/mnt/data1/pastebin-clean/zkperf/zkperf-witness/src/ringbuffer.rs`
(**outside git** — not a tracked change).

- Removed the 3 per-push debug `eprintln!`s (stderr + two extra mutex
  re-locks per push in a throughput tool).
- Spill I/O no longer runs under the lock: drain to a local `Vec` in a short
  lock scope, release, then `append_spill_entries`.
- `static mut RING_INNER` + `unsafe` → `std::sync::OnceLock`; poisoned mutex
  recovers via `PoisonError::into_inner`; serialization failures logged, not
  swallowed; dead `head`/`capacity` fields and the `AtomicUsize` import
  removed; doc comment corrected (it is neither lock-free nor a ring).
- Verified in a temp copy: `cargo check` clean (0 warnings in the file),
  `cargo test --lib` 3/3. The full workspace can't resolve — root
  `Cargo.toml` points at a missing `../erdfa-canonical/bindings/rust`.
- **8 copies / 4 md5 families** exist; only the live source was fixed. The
  three 106-line copies under `pastebin-clean/_gen/*/deps/` and
  `time-2026/04-april/26/zkperf/` still carry the hot-path `eprintln!` bug
  (build deps, not source). Porting the fix there is optional/pending.

## 7. Pending

1. **GPU work sweep** across the kiro chats — the ask that motivated the
   snapshot (not yet done).
2. Optional: port the ringbuffer fix to the `_gen` vendored copies.
3. Commit the enricher changes.

## 8. Reproduce

```bash
# refresh the snapshot (optional; one already exists)
python3 /home/mdupont/dotagents/task-enricher/scripts/kiro_chat_export.py

# full checks
cd /home/mdupont/dotagents && cargo test --release -p task-enricher   # 99/99
./target/release/task-enricher enrich --dir <task-dir> --focus agent-logs

# a task that must surface old GPU/cargo2nix work:
#   SYSTEM.md naming cargo2nix / split-decls / vendor / workspace
# → ENRICHMENT.md "### Agent Logs" lists 2025-12/2026-01 snapshot files
```
