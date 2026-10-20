# 20261007-pretty-names-design

## Problem

`pastebinit` posts to `/var/spool/uucp/pastebin/` with a long unwieldy filename derived
from the title and the backend metadata. For the decision record we just posted, the
file is:

```
/var/spool/uucp/pastebin/20261007_153106_decision_record_20261007_141700_pr_coordination_283_282_104_api_url_git_repo_mfng_tracker_repo_mfng_tracker_repo_mfng_tracker.txt
```

That is ugly, and it makes the artifact hard to reference in docs, PRs, and ticketcat.

## What "pretty names" should mean here

- readable base name
- predictable date prefix
- no repeated git repo metadata baked into the filename
- still identifiable in the UUCP spool
- ideally a companion receipt/index so the web app or docs can find the pretty-named
  artifact without scanning filenames

## Constraints

- `/var/spool/uucp/pastebin/` is owned by `kant:kant` and is not writable by my uid.
- `pastebinit` is what currently posts into that spool, and it uses the default solana
  pastebin backend.
- `~/projects/pastebin/deploy.sh` deploys the pastebin *service* (Nix build, systemd
  restart), not a rename/edit of individual spool artifacts.
- The pastebin service already has multiple active units:
  - `kant-pastebin.service`
  - `kant-pastebin-relay.service`
  - `kant-pastebin-dev.service`
  - `kant-pastebin-lean-dev.service`
  - `kant-pastebin-lean-relay.service`

## Proposed design

1. Create a pretty-name receipt index in the pastebin project under `docs/decisions/`
   that records:
   - date
   - pretty name
   - original ugly UUCP filename
   - pastebinit URL
   - repo decision docs
   - related PRs
2. If the pastebin web/service supports it, publish the pretty name + receipt through
   the pastebin web surface instead of relying on the ugly UUCP filename.
3. If a rename in `/var/spool/uucp/pastebin/` is actually wanted, that must be done by
   a path that has `kant:kant` write access, not by my uid. That may be:
   - a pastebin service endpoint that manages its own spool, or
   - an authorized deploy/activate path, or
   - a permission change you explicitly authorize.
4. Do not assume `deploy.sh` edits spool filenames. It restarts services and rebuilds
   the pastebin service; it does not currently touch `/var/spool/uucp/pastebin/` spool
   rename logic.

## Current pretty-name receipt

- `docs/decisions/20261007-pr-coordination-283-282-104.md`
