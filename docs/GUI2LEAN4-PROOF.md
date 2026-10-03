# GUI2Lean4 — recorded browser proof for the kant paste page

Proves in a real browser (headless Chrome via CDP) that the full flow works:
**open invite link → auto-join room → proved wasm kernel loads → type → Post → posted (cursor N)**.

Recordings from the 2026-09-29 run (after the invite-join fix, commit `2a545ba`):

- `gui2lean4-kant-proof-live.gif` — the screencast frames as captured (15 frames @ 4fps)
- `gui2lean4-kant-proof-steps.gif` — the 4 step screenshots as a storyboard

## Reproduce

Prereqs: chrome/chromium, node (nix profile), this repo, ffmpeg for the GIF.

```bash
# 1. headless Chrome with CDP (PrivateNetworkAccess flags let a public page
#    reach a LAN relay during local testing; harmless for the CF twin):
rm -rf /tmp/cdp-profile
setsid google-chrome --headless=new --remote-debugging-port=9222 \
  --user-data-dir=/tmp/cdp-profile --no-first-run --no-default-browser-check \
  --no-sandbox \
  --disable-features=BlockInsecurePrivateNetworkRequests,PrivateNetworkAccessRespectPreflightResults \
  about:blank >/tmp/chrome-cdp.log 2>&1 &

# 2. run the proof — navigates the vaciu owner invite (via the CF relay twin),
#    records screencast frames + a11y/DOM evidence + per-step screenshots,
#    then mints a fresh 5-post group pass for sharing:
cd ~/projects/pastebin-lean
rm -rf /tmp/gui2lean4-kant
node scripts/gui2lean4-kant-proof.mjs

# expected output:
#   [step 1] loaded        postEnabled=false
#   [step 2] auto-joined   postEnabled=true
#   [step 3] typed
#   [step 4] posted        log contains "posted (cursor N)"
#   pass signature valid: true | room matches: true
#   SHARE_LINK=https://kant-zk-pastebin.pages.dev/paste.html#kzpass…
```

## Artifacts (in `/tmp/gui2lean4-kant/`)

| file | what |
|---|---|
| `01-loaded.png` … `04-posted.png` | step screenshots |
| `screencast-frames.json` | raw CDP screencast frames (base64 pngs) |
| `evidence.json` | a11y landmarks, interactive controls, telemetry per step |
| `share-pass-link.txt` | the freshly minted 5-post pass link |

## Render the GIFs

```bash
cd /tmp/gui2lean4-kant
python3 -c "
import json, base64
frames = json.load(open('screencast-frames.json'))
import os; os.makedirs('frames', exist_ok=True)
for i, b in enumerate(frames):
    open(f'frames/f{i:04d}.png','wb').write(base64.b64decode(b))"
ffmpeg -y -framerate 4 -i frames/f%04d.png -vf scale=900:-1:flags=lanczos recording-live.gif
```

## What the proof caught

| bug | symptom | fix |
|---|---|---|
| auto-join missing | pass/invite links opened to an empty join box | `737464d` |
| invite-join post crash | `copyPass` on a bare invite threw inside an uncaught promise; Post did nothing, no error shown | `2a545ba` |
| PNA blocking (local only) | Chrome refuses public-page→private-IP fetch (`LocalNetworkAccessPermissionDenied`); mint local tests against the CF relay twin | n/a (environment) |

Page exceptions are invisible in the page log because the click handler dies in
an uncaught promise — always capture `Runtime.exceptionThrown` over CDP.
