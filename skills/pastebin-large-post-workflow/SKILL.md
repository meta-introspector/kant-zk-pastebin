---
name: pastebin-large-post-workflow
description: Work on Kant Pastebin large-post split/share behavior. Use when fixing or extending split, share, ZIP download, chunk upload, or deployment docs for large pastes.
---

# Pastebin Large Post Split/Share Workflow

## When to Use

Use this skill when working on:

1. Splitting large pastes without loading full raw content into the browser.
2. Server-side split endpoints that accept `paste_id`.
3. ZIP downloads of split chunks.
4. Uploading split chunks as separate pastes.
5. Share button fallback behavior.
6. Nix/system-manager deployment of `kant-pastebin`.

## Current Architecture

The post split page uses the paste ID only. It does not render a full-content `<textarea>` and does not call the generic `/api/split` endpoint with raw text.

Flow:

1. Browser opens `/paste/{id}/split`.
2. Browser sends `{ paste_id, chunk_size, unit, split_mode, overlap }` to `/api/split-paste`.
3. Server resolves stored paste content by ID.
4. Server splits content and returns summary metadata plus a tiny preview.
5. Browser can request `/api/split-download` for a ZIP or `/api/split-upload` for chunk pastes.

## Endpoints

### `POST /api/split-paste`

Use for previewing split results for a stored paste.

Request fields:

- `paste_id` or `id`: paste identifier.
- `chunk_size`: byte count, default `102400`.
- `unit`: currently sent as `byte`.
- `split_mode`: `exact`, `line`, or `word`.
- `overlap`: overlap bytes, usually `0`.
- `preview_chars`: optional per-chunk preview limit.
- `preview_chunks`: optional number of chunks to preview.

Response includes:

- `chunks`
- `chunk_size`
- `overlap`
- `unit`
- `split_mode`
- `total_size`
- `word_count`
- `estimated_tokens`
- `preview_chunks`

Do not return all chunk bodies from this endpoint.

### `POST /api/split-download`

Use for downloading all chunks as a ZIP.

Accepts either:

- `paste_id` or `id`
- raw `content`

Response is `application/zip` with files named:

```text
part_0001.txt
part_0002.txt
part_0003.txt
...
```

No manifest or extra files should be added.

### `POST /api/split-upload`

Use for creating one paste per chunk and one index paste.

Accepts either:

- `paste_id` or `id`
- raw `content`

Returns:

- `chunks`
- `chunk_ids`
- `index_id`
- `url`
- `total_size`
- `word_count`
- `estimated_tokens`

## Content Resolution

`resolve_split_content()` chooses content in this order:

1. `paste_id` or `id`
2. raw `content`

For paste IDs:

1. Read the paste index from `UUCP_SPOOL`.
2. Find the entry with matching `id`.
3. Read `entry.uucp_path`.
4. Fall back to `$UUCP_SPOOL/<paste_id>.txt`.

`read_paste_content()` must extract actual content from the stored paste wrapper. Current format places `Sheaf:` before the content and RDFa after it. Find `Sheaf:` in the header, skip the blank line after it, then stop before the first `<div`.

## Split Page Requirements

The split page must:

- Avoid a full raw-content `<textarea>`.
- Avoid returning all chunk bodies for preview.
- Show chunk-size choices from 128 KB through 8 MB.
- Default chunk size to 1 MB.
- Show boundary choices: Newline, Word boundary, Exact bytes.
- Default boundary to Exact bytes.
- Show only a tiny preview, e.g. 500 characters for 3 chunks.
- Keep Download ZIP and Upload Chunks as Pastes actions.

## Share Button Requirements

The post page Share button must open a destination menu with:

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

The chat/search prompt is built from the paste title, paste URL, and up to the first 4000 characters of paste content. Search destinations use the title plus the first 1000 characters. Native sharing still falls back to URL copying when unavailable.

Do not rely on `navigator.share` without a fallback.

## Offline Share Menu Test

The share menu renderer and destination wiring are covered by a no-HTTP CLI test:

```bash
make test-share-menu
```

Equivalent direct command:

```bash
nix develop -c cargo run --bin kant-pastebin -- test-share-menu
```

## Upload and Paste Metadata

Normal paste, file upload, archive upload, and archive aggregate flows now carry title and description metadata through the stored paste header, `.meta` sidecar, `index.jsonl`, and JSON responses.

### Home form

The home form includes `title` and `description` fields. When no file is selected, `/paste` receives:

- `content`
- `title`
- `description`
- `keywords`
- `reply_to`

For JSON paste creation:

1. Use the user-provided `title` when present.
2. Otherwise use the HTML `<title>` if the content is HTML.
3. Otherwise use `tagging::auto_describe(content)` when tags exist.
4. Otherwise fall back to `untitled`.
5. Use the user-provided `description` when present.
6. Otherwise use `tagging::auto_describe(content)`.
7. Store `Description:` in the paste header.
8. Store `description` in the paste index entry.

### File upload

`POST /upload` accepts multipart fields:

- `file`
- `title`
- `description`

Behavior:

1. Derive the title from `title` if present.
2. Otherwise derive it from the uploaded filename with `archive_name_title()`.
3. Derive the description from `description` if present.
4. Otherwise derive it from text/HTML/JSON content with `file_description()`.
5. Write `Title:` and `Description:` to the `filename.meta` sidecar.
6. Write `description` to `index.jsonl`.
7. Return `title` and `description` in the JSON response.

### Archive upload

`POST /upload-archive` accepts multipart fields:

- `file`
- `title`
- `description`

Behavior:

1. Extract the archive with `crate::archive::extract()`.
2. Derive the archive title from `title` if present, otherwise from the archive filename.
3. Derive the archive description from `description` if present, otherwise from the filename, entry count, and byte size.
4. Store the derived title and description on `ArchiveResult`.
5. Write the raw archive file and `Title:` / `Description:` metadata to the spool.
6. Write `description` to `index.jsonl`.
7. Return `title` and `description` in the JSON response.

### Archive aggregate generation

`POST /archive-generate/{session_id}` now creates aggregate paste files named from the source archive/post title instead of generic `allm_...` names:

```text
YYYYMMDD_HHMMSS_all_<slug>.txt
```

The generated aggregate paste:

1. Uses the archive result `title`.
2. Uses the archive result `description`.
3. Stores both values in the paste header.
4. Stores `description` in the paste index entry.
5. Returns `title` and `description` in the JSON response.

### Archive file posting

`POST /archive-post-file/{session_id}/{idx}` creates a paste from a single extracted archive entry. Its description is currently derived as:

```text
From archive: <archive title>
```

The generated paste stores that description in the header and index entry.

## allm Rename Tool

Existing archive aggregate pastes generated as generic `allm.txt` / `_allm_...` files can be renamed in-place with the CLI tool:

```bash
make rename-allm-pastes
```

Equivalent direct command:

```bash
nix develop -c cargo run --bin kant-pastebin -- rename-allm-pastes
```

Behavior:

1. Scan `index.jsonl` for entries whose title or filename indicates an `allm` aggregate.
2. Read each paste header and body.
3. Derive a nicer title from the `Source archive:` line.
4. Derive a description from the selected file count, archive title, and paste size.
5. Update `Title:` and `Description:` in the paste file header.
6. Update `title`, `description`, `cid`, and `witness` in the matching index entry.
7. Preserve malformed or legacy index lines unchanged.

Preview only:

```bash
make rename-allm-pastes
```

Apply changes:

```bash
make rename-allm-pastes-apply
```

Optional flags:

```bash
nix develop -c cargo run --bin kant-pastebin -- rename-allm-pastes --apply --limit 20
nix develop -c cargo run --bin kant-pastebin -- rename-allm-pastes --apply --rename-files
```

`--rename-files` also rewrites the physical filename/id to include the archive title slug; leave it off to preserve existing paste URLs.

## Deployment

Use the flake and repo deploy script:

```bash
nix build .#kant-pastebin --print-out-paths
./deploy.sh
```

`deploy.sh` resolves its physical script directory and uses local branch deployment by default:

```text
git+file://${PASTEBIN_DIR}?ref=${PASTEBIN_BRANCH}#systemConfigs.kant-pastebin-only
```

Do not deploy from `/home/mdupont/pastebin/target/release`.

If nix-daemon is dead after an OOM build:

```bash
sudo -n systemctl start nix-daemon.service
./deploy.sh
```

## Verification Checklist

Before finishing large-post split, share, upload, archive metadata, and allm rename work:

1. Build with `nix build .#kant-pastebin --print-out-paths`.
2. Run `make test-share-menu`.
3. Deploy with `./deploy.sh`.
4. Confirm `kant-pastebin.service` is active.
5. Open a split page and confirm there is no full raw `<textarea>`.
6. Confirm `/api/split-paste` returns `preview_chunks`, not `contents`.
7. Confirm `/api/split-download` returns a ZIP containing only `part_*.txt`.
8. Confirm `/api/split-upload` creates chunk pastes and an index paste.
9. Confirm Share opens the destination menu and Native Share falls back to URL copying when unavailable.
10. Confirm Claude, OpenAI / ChatGPT, Grok, X, NightCafe, DeepSeek Chat, GitHub, and Hugging Face menu items generate the expected URLs or copy prompt fallback.
11. Confirm the home form includes `title` and `description` fields.
12. Confirm `/paste`, `/upload`, `/upload-archive`, and `/archive-generate/{session_id}` store title and description in headers, metadata, index entries, and JSON responses.
13. Confirm archive aggregate paste filenames use the source archive/post title slug instead of generic `allm_...` names.
14. Run `make rename-allm-pastes` and confirm it previews derived titles/descriptions from `Source archive:`.
15. Run `make rename-allm-pastes-apply` only after confirming the preview, then confirm `index.jsonl` and paste headers contain the new title/description values.

## Known Caveats

- The original post view still renders full content in a `<pre>`. For very large pastes, opening the post itself may still be expensive.
- `api_split_paste` builds split chunks in memory. This is fine for ~10MB smoke tests, but much larger posts need streaming or hard chunk-count limits.
- Add minimum chunk-size or maximum chunk-count validation if users can request tiny chunks that create thousands of files.
