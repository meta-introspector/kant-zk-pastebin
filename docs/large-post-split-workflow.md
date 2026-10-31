# Kant Pastebin Large Post Split/Share Workflow

## Purpose

This workflow documents the current server-side split/share implementation for large pastes, especially ~10MB posts that should not be moved through browser JSON or rendered as many DOM previews.

## Current Design

The post split page reads only the paste ID from the URL and sends that ID to the server. The server loads the stored paste content, splits it, and returns summary metadata plus a small preview. The browser never receives every chunk body from the split-preview endpoint.

The split page still supports:

- Downloading all chunks as a ZIP of `.txt` files
- Uploading split chunks as separate pastes
- Selecting chunk size from a dropdown
- Selecting split boundary mode
- Sharing the paste URL with native sharing when available and clipboard fallback otherwise

## Routes

### `POST /api/split-paste`

Splits a stored paste without returning all chunk bodies.

Request:

```json
{
  "paste_id": "20260620_043153_split_button_smoke_split_test",
  "chunk_size": 1048576,
  "unit": "byte",
  "split_mode": "exact",
  "overlap": 0,
  "preview_chars": 500,
  "preview_chunks": 3
}
```

Response shape:

```json
{
  "chunks": 11,
  "chunk_size": 1048576,
  "overlap": 0,
  "unit": "byte",
  "split_mode": "exact",
  "total_size": 10485760,
  "word_count": 123456,
  "estimated_tokens": 250000,
  "preview_chunks": [
    {
      "index": 0,
      "byte_len": 1048576,
      "text": "first 500 characters..."
    }
  ]
}
```

Implementation: `src/handlers.rs:3656`

### Archive sessions survive a restart

An archive upload returns a `session_id`, and that session is now written to disk as well as kept in memory:

- `POST /upload-archive` saves `$UUCP_SPOOL/archive_sessions/<session_id>.json` (the full `ArchiveResult`: entries, per-file content, prefixes/ngrams/tags). A write failure is logged and does not fail the upload — the archive file and its metadata sidecar are already in the spool.
- On startup `handlers::load_archive_sessions()` reads every `*.json` back into the in-memory map and logs `Loaded N archive sessions from disk`.
- `GET /browse-archive/{id}`, `/archive-pattern`, `/archive-split`, `/archive-generate` and `/archive-preview` all resolve through `get_archive_session()`, which checks memory first and falls back to the file. So an archive browsed before a redeploy still opens afterwards.
- The session file is the only copy: deleting it makes the session unavailable, and re-uploading the same bytes yields the same `session_id` (it is the first 16 hex characters of the SHA-256 of the upload).

### `POST /archive-pattern/{session_id}`

Selects the files of an uploaded/browsed archive by pattern, so the selection can be split. The session is the one `/upload-archive` returned (see *Archive sessions survive a restart* above for where it lives).

Request:

```json
{
  "pattern": "src/**/*.rs"
}
```

Pattern language:

- `*` matches within one path segment; `**` crosses `/` (`**/` also matches zero directories); `?` is one character; everything else is literal.
- A pattern with no `/` also matches the bare file name, so `*.md` finds `docs/README.md`.
- A pattern ending in `/` selects everything under that directory.
- Plain text (no `*`/`?`, not ending in `/`) is a case-insensitive path search that also consults the archive's prefix, ngram and tag indexes (`src/archive_utils.rs`, `PatternStore`).

Response:

```json
{
  "pattern": "src/**/*.rs",
  "matches": ["./src/main.rs", "./src/db/schema.rs"],
  "count": 2,
  "total": 5
}
```

Paths are the archive's own entry paths, `./` prefix included — identical to the checkbox `value`s in the viewer.

### `POST /api/split-download`

Downloads split chunks as a ZIP. Accepts either `paste_id` or raw `content`.

Request with paste ID:

```json
{
  "paste_id": "20260620_043153_split_button_smoke_split_test",
  "chunk_size": 1048576,
  "unit": "byte",
  "split_mode": "exact",
  "overlap": 0
}
```

Response:

- Content type: `application/zip`
- File names: `part_0001.txt`, `part_0002.txt`, etc.
- No manifest or extra files

Implementation: `src/handlers.rs:3720`

### Archive viewer pattern bar

`GET /browse-archive/{session_id}` carries a pattern bar above the file table:

- **🎯 Select matching** posts the pattern to `/archive-pattern/{session_id}` and checks the matching rows, so **✂️ Split Selected** and **📝 Generate allm.txt** act on the pattern's selection.
- **🔗 Share pattern** puts the pattern in the page URL (`?pattern=…`, percent-encoded) and copies the link; opening that link re-applies the pattern on load. Rebuilding a pattern store per call is cheap — it is derived from the session's stored entries, not persisted separately.

The pattern response returns the same path strings the checkboxes carry (`./src/main.rs`, not `src/main.rs`), so the client can check rows by value with no path normalisation.

### Beta verification (2026-10-28)

Run against `https://solana.solfunmeme.com/pastebin/beta/` (`v0.2.0`, backend `127.0.0.1:8085`, final build `172b27e` / `build_time=2026-10-28T14:04:05Z`) with the five-file fixture in `.archive-test-fixture/sample.tar.gz` (5 files, 4 directories):

| step | call | result |
|---|---|---|
| upload | `POST /upload-archive` (`sample.tar.gz`) | `session_id=ca99711e63f45e6e`, 10 entries, `archive_sessions/ca99711e63f45e6e.json` written |
| glob | `{"pattern":"*.rs"}` | 2 of 5 files: `./src/main.rs`, `./src/db/schema.rs` |
| glob | `{"pattern":"src/**/*.rs"}` | same 2 (matches bare and nested paths) |
| dir | `{"pattern":"docs/"}` | 2 of 5: `./docs/README.md`, `./docs/notes.txt` |
| bare name | `{"pattern":"*.md"}` | 1 of 5: `./docs/README.md` |
| miss | `{"pattern":"lean"}` | 0 of 5, no error |
| split | `POST /archive-split` with the 2 glob matches | 1 chunk, `/paste/split_index_20261028_135745` |
| restart | `systemctl restart kant-pastebin-beta`, then the same session | `Loaded 1 archive sessions from disk`; viewer 200, pattern still resolves |
| share link | headless chromium, `?pattern=src%2F**%2F*.rs` | bar auto-applied: 2 of 5 checked, Split landed on `/paste/split_index_20261028_141506` |
| no match | headless chromium, `?pattern=nomatch-xyz` | script throws (`pattern … selected no rows`) — the negative control |

The browser run is `scripts/archive-viewer-check.mjs` (puppeteer-core from the repo's `node_modules`):

```bash
S=$(cat logs/pattern-test-session.txt)
CHROME=/home/mdupont/.nix-profile/bin/chromium \
CHROME_ARGS="--host-resolver-rules=MAP|solana.solfunmeme.com|127.0.0.1;--ignore-certificate-errors" \
  node scripts/archive-viewer-check.mjs https://solana.solfunmeme.com/pastebin/beta "$S" 'src/**/*.rs'
```

`CHROME_ARGS` entries are `;`-separated and `|` becomes a space, because the host-resolver rule needs spaces inside one argv element. The `CHROME_ARGS` in that command are only needed because this host resolves `solana.solfunmeme.com` to a LAN address first; the script itself is host-agnostic. It exits non-zero when the pattern does not reach the input, selects zero rows, or Split does not navigate — the only console error left on a passing run is the site-wide `/favicon.ico` 404.

### Two defects found by the run, both fixed

- **Sessions were never written.** `archive_store::save_session` existed and `load_archive_sessions()` ran at startup, but no upload path called `save_session`, so `$UUCP_SPOOL/archive_sessions/` did not exist and every restart emptied the store — `GET /browse-archive/<id>` 404'd after a redeploy. `POST /upload-archive` now saves the session (a failed write is logged, not fatal), which is what makes the persistence rows above true.
- **Every paste page loaded a broken script.** The template had `<script src="{share_menu}/static/a11y.js">`, interpolating the share-menu *HTML* into a `src` attribute, so the browser requested `/paste/%3Cdiv%20class=` and got a 404; there was also no route serving `static/` at all. The tag is now `{bp}/static/a11y.js` and `main.rs` mounts `actix_files::Files::new("/static", "static")` (`actix-files` was already a dependency). `GET /static/a11y.js` returns `text/javascript` on the backend and through nginx.

### `POST /api/split-upload`

Splits a stored paste or raw content and writes each chunk as a separate paste, plus an index paste.

Request:

```json
{
  "paste_id": "20260620_043153_split_button_smoke_split_test",
  "title": "split_20260620_043153_split_button_smoke_split_test",
  "chunk_size": 1048576,
  "unit": "byte",
  "split_mode": "exact",
  "overlap": 0
}
```

Response:

```json
{
  "chunks": 11,
  "chunk_ids": ["..."],
  "index_id": "...",
  "url": "/paste/...",
  "total_size": 10485760,
  "word_count": 123456,
  "estimated_tokens": 250000
}
```

Implementation: `src/handlers.rs:3780`

## Content Extraction

`resolve_split_content()` accepts `paste_id`, `id`, or raw `content`.

For stored pastes:

- `read_paste_content_by_id()` first checks the paste index under `UUCP_SPOOL`.
- It then falls back to `$UUCP_SPOOL/<paste_id>.txt`.
- `read_paste_content()` extracts the actual content from the stored paste format.

Current stored paste format:

```text
--- id ---
Title: ...
Keywords: ...
CID: ...
Witness: ...
IPFS: ...
DASL: ...
Reply-To:
Sheaf: ...

actual content


<div typeof="erdfa:SheafSection ...">...
```

The extraction logic finds `Sheaf:` in the header, skips the blank line after it, then returns content before the RDFa `<div>`.

Implementation: `src/handlers.rs:1279`

## Split Page UI

The post split page is rendered by `render_split_paste()` in `src/view.rs`.

Current UI constraints:

- No `<textarea>` containing the full raw paste
- No JSON response containing all chunk bodies for the preview
- Chunk-size dropdown values:
  - 128 KB
  - 256 KB
  - 512 KB
  - 1 MB default
  - 2 MB
  - 4 MB
  - 8 MB
- Boundary dropdown values:
  - Newline
  - Word boundary
  - Exact bytes default
- Preview limit:
  - 500 characters per chunk
  - 3 chunks

Implementation: `src/view.rs:80`

## Share Button

The post page uses a destination menu from the Share button. The menu includes:

- Native Share
- Copy URL
- Copy Prompt
- Claude
- OpenAI / ChatGPT
- Grok
- X
- NightCafe
- DeepSeek Chat
- Search GitHub
- Search Hugging Face

The prompt sent to chat/search destinations is built from the paste title, paste URL, and up to the first 4000 characters of paste content. Search destinations use the title plus the first 1000 characters. NightCafe opens the create page and copies the prompt because NightCafe does not expose a stable prompt prefill URL.

Implementation: `src/handlers.rs:685`

## Deployment

Build the application binary from the flake:

```bash
nix build .#kant-pastebin --print-out-paths
```

Deploy through the repo script:

```bash
./deploy.sh
```

`deploy.sh` resolves its physical script directory with `pwd -P` and uses the flake target `systemConfigs.kant-pastebin-only` by default. Do not deploy from `/home/mdupont/pastebin/target/release`.

If nix-daemon was killed by OOM during a build, restart it and retry:

```bash
sudo -n systemctl start nix-daemon.service
./deploy.sh
```

## Verification Commands

Split-preview endpoint:

```bash
python3 - <<'PY'
import json, urllib.request
base = 'http://127.0.0.1:8090'
base_path = '/pastebin'
pid = 'PASTE_ID_HERE'
body = json.dumps({
    'paste_id': pid,
    'chunk_size': 1048576,
    'unit': 'byte',
    'split_mode': 'exact',
    'preview_chars': 500,
    'preview_chunks': 3,
}).encode()
req = urllib.request.Request(
    base + base_path + '/api/split-paste',
    data=body,
    headers={'Content-Type': 'application/json'},
    method='POST',
)
with urllib.request.urlopen(req, timeout=120) as r:
    print(r.read().decode())
PY
```

ZIP endpoint:

```bash
python3 - <<'PY'
import io, json, urllib.request, zipfile
base = 'http://127.0.0.1:8090'
base_path = '/pastebin'
pid = 'PASTE_ID_HERE'
body = json.dumps({
    'paste_id': pid,
    'chunk_size': 1048576,
    'unit': 'byte',
    'split_mode': 'exact',
}).encode()
req = urllib.request.Request(
    base + base_path + '/api/split-download',
    data=body,
    headers={'Content-Type': 'application/json'},
    method='POST',
)
with urllib.request.urlopen(req, timeout=120) as r:
    data = r.read()
z = zipfile.ZipFile(io.BytesIO(data))
print(z.namelist()[:10])
print(len(z.namelist()))
print(all(n.endswith('.txt') for n in z.namelist()))
PY
```

## Operational Lessons Learned

- Existing archive aggregate pastes may have generic `allm.txt` / `_allm_...` filenames and headers even when newer archive upload code can derive better metadata.
- The allm rename tool should preview first and only apply after confirming the derived titles/descriptions:
  ```bash
  make rename-allm-pastes
  make rename-allm-pastes-apply
  ```
- The allm tool preserves existing paste URLs by default. Use `--rename-files` only when physical filenames and paste IDs should change too.
- The first allm index rewrite implementation dropped malformed/legacy `index.jsonl` lines. The fixed implementation stores raw index lines and only replaces matching parsed records.
- Spool writes must be run as the user that owns `/mnt/data1/spool/uucp/pastebin`; do not use `sudo` for the tool itself.
- Deploy through `./deploy.sh` from the current repo checkout and local branch. Do not deploy from `/home/mdupont/pastebin/target/release`.
- `deploy.sh` may report unrelated legacy-service or nginx warnings. The important pastebin check is that `kant-pastebin.service` is active and `http://127.0.0.1:8090/` returns HTTP 200.

## Threaded View and Similar Posts

Threaded views are built from `Reply-To` metadata in `index.jsonl` and paste headers.

Routes:

- `GET /threads?page=N&limit=N` lists paginated thread roots.
- `GET /thread/{id}?page=N&limit=N` renders a paginated threaded view.
- `GET /api/thread/{id}?page=N&limit=N` returns the same paginated thread as JSON.
- `GET /api/similar/{id}?limit=N` returns scored similar posts using shared keywords, metadata terms, ngrams, and content overlap.

The thread page includes a "Find similar" button for each post. The similarity API returns a numeric `score` so the UI can rank posts instead of relying only on keyword matches.

The thread page also includes an "Export" link:

- `GET /thread/{id}/export?max_bytes=N` downloads the full thread as `thread-{id}.txt`.
- If the exported text exceeds `max_bytes`, the route returns a zip file containing `thread-{id}-part-001.txt`, `thread-{id}-part-002.txt`, and so on.
- The default split threshold is 5 MB, clamped between 1 byte and 50 MB.

## Known Caveats

- The original post view still renders the full content in a `<pre>`. If opening a ~10MB paste hangs, the next step is lazy-loading or capped preview rendering for the post view itself.
- `api_split_paste` still builds the split chunk vector in memory to compute metadata and previews. This is acceptable for ~10MB smoke tests but should be streamed or capped for much larger posts.
- Consider adding maximum chunk-count or minimum chunk-size validation if tiny chunk sizes can create thousands of chunks.
