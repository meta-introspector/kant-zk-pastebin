# Task: pastebin-unmanaged-nginx-configs

**Status:** DONE (2026-10-03) — committed `a032a84` in system-manager, **not pushed** — **a rebuild from profile loses the live chat**
**Project:** numtide/system-manager, deployed on this host
**Found:** 2026-10-02

## Problem

Three configs live in `/etc/nginx` that nothing in the repository produces:

| file | what it does |
|---|---|
| `nginx/locations.d/kant-p2p-relay.conf` | **publishes the live p2p chat** at `/p2p-relay/` |
| `cloudflare-coordination.conf` | Cloudflare coordination endpoints |
| `forgejo.conf` | a forgejo instance |

`deploy-nginx-services.sh` syncs `nginx/services.d/` and `nginx/locations.d/`
and reloads, but `kant-p2p-relay.conf` is not in the repo at all — it exists
only on disk. A rebuild from the NixOS profile, or any fresh install from this
configuration, produces a server with no `/p2p-relay/`, and therefore no chat
and no file share.

For contrast, `nginx/services.d/pastebin.conf` *is* in the repo and carries a
comment recording that the chat is at `/p2p-relay/` and that
`pastebin-lean.conf` is never deployed — so the two files were confused at some
point, and `pastebin-lean.conf` remains in the repo as a dead config.

## Fix

1. Move `kant-p2p-relay.conf` into `nginx/locations.d/` in the repo so
   `deploy-nginx-services.sh` manages it, and confirm the deployed file matches
   byte for byte before committing.
2. Decide the fate of `cloudflare-coordination.conf` and `forgejo.conf` — same
   treatment, or delete them if those services are gone.
3. Delete `nginx/pastebin-lean.conf`, which nothing includes, or add a comment
   saying why it exists so the next reader stops wondering.

## Verify

```sh
cd ~/projects/system-manager
bash deploy-nginx-services.sh && nginx -t
curl -s -o /dev/null -w '%{http_code}\n' https://solana.solfunmeme.com/p2p-relay/
# want 200
```


## Resolution (2026-10-03)

Four configs existed only in `/etc` and were invisible to the Nix profile:

| config | publishes | was it live? |
|---|---|---|
| `services.d/kant-p2p-relay.conf` | the p2p chat | yes |
| `services.d/forgejo.conf` | the git forge | yes |
| `services.d/cloudflare-coordination.conf` | the CF dashboard | yes |
| `locations.d/tracker-ci-results.conf` | build artifacts | yes |

The fourth was invisible to the original report because it lives in
`locations.d`, not `services.d`. Found only after the deploy script was taught
to check both directories.

All four are now versioned in `~/projects/system-manager/nginx/` and deployed
through `deploy-nginx-services.sh`.

### The check now fails instead of noting

`--check` counted nothing, printed one line per untracked file, and exited 0 —
so it read as information rather than as a fault. It now counts them and exits
1, naming each file and saying what a rebuild will do. It deletes nothing: the
file stays in `/etc` and the deploy refuses to claim success until it is
versioned or removed deliberately.

### Also recorded

`nginx/README.md` — the rule, plus two traps found while doing this:

- `services.d` and `locations.d` share one include glob, so a `location`
  defined in both makes `nginx -t` fail with `duplicate location`. This is how
  `/pastebin-dev/` collided with the existing `/pastebin-dev/`.
- the script skips its reload when it synced nothing, so a config that reached
  `/etc` by hand needs an explicit `systemctl reload nginx`. Cost one confusing
  404 during this work.

### Verified

`nginx -t` clean; all six public services answer 200 (`/p2p-relay`, `/forgejo`,
`/cloudflare`, `/tracker/ci-results`, `/pastebin`, `/pastebin-dev-int`), and the
live chat was re-checked end to end with two isolated browsers — a line crossed.

Still open: the system-manager commit is **not pushed**.
