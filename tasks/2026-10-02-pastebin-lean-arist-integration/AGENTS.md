# Agent Conventions — 2026-10-02-pastebin-lean-arist-integration

## Repo facts
- pastebin-lean: `/home/mdupont/projects/pastebin-lean`, main = `bbac0ab`.
  Real remote = local mirror `/mnt/data1/git/github.com/mdupont/kant-zk-pastebin.git`
  (GitHub kant-zk-pastebin 404s).
- arist: `/mnt/data1/time-2026/05-may/07/arist`, main = `4f4a66a79`.
  Mirror remote `local` is diverged — never force-push.

## Common commands
```bash
# pastebin-lean suite (19 suites)
cd ~/projects/pastebin-lean && for t in web/*-test.mjs test/*.mjs; do node $t; done

# e2e (two-browser, in-process mock relay)
node scripts/kant-file-e2e.mjs

# arist branch/worktree audit
cd /mnt/data1/time-2026/05-may/07/arist && git worktree list && git status -sb
```

## Rules
- Read SYSTEM.md before touching branches or worktrees in either repo.
- Worktree removal is destructive: check for live agent PIDs first.
- Commit format: `feat(scope): description` / `fix(scope):` / `test(scope):`.
