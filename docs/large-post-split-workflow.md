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

## Known Caveats

- The original post view still renders the full content in a `<pre>`. If opening a ~10MB paste hangs, the next step is lazy-loading or capped preview rendering for the post view itself.
- `api_split_paste` still builds the split chunk vector in memory to compute metadata and previews. This is acceptable for ~10MB smoke tests but should be streamed or capped for much larger posts.
- Consider adding maximum chunk-count or minimum chunk-size validation if tiny chunk sizes can create thousands of chunks.
