---
name: pastebin-lean-arist-integration
description: Record of the 2026-10-02 integration session — pastebin-lean main=bbac0ab (file-drop + p2p-wasm + hermetic tests, 19 suites green) and arist main=4f4a66a79 (vaciu stack FF). Read before touching branches or worktrees in either repo.
priority: HIGH
---

# pastebin-lean + arist integration — 2026-10-02

See [SYSTEM.md](SYSTEM.md) for the full merge table, SHAs, and worktree
disposition. Key facts:

- pastebin-lean: `main` = `bbac0ab` (branch `integrate/20261002`), pushed to
  local mirror `/mnt/data1/git/github.com/mdupont/kant-zk-pastebin.git`.
  GitHub remote 404s — mirror is authoritative.
- arist: `main` = `4f4a66a79` (FF of fix/vaciu-pass-safe-proof, 45 commits).
  Local mirror `local` remote DIVERGED (June work) — see task
  `2026-10-03-arist-local-main-merge-decision`.
- p2p tests are hermetic: `P2PApp.publish` takes `rpcBase`/`gwBase`; never
  assume 127.0.0.1:5001 is empty (a live kubo runs there).
