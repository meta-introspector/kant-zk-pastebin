# Pastebin Deploy — Diagnosis Runbook

## Symptom: Step 3 fails — "system-manager config build failed"

### Case 1: `error: cannot coerce a set to a string: { LOG_MODE = "canned"; PORT = "3318"; }`

**Root cause (two layers):**
1. **Nix layer**: `Environment = { PORT = "3318"; ... }` written inside
   `serviceConfig` — NixOS systemd options expect `Environment` as a *string*
   (`"PORT=3318 LOG_MODE=canned"`), not an attrset. The correct attrset form is
   the *service-level* `environment = { PORT = "3318"; };` option.
2. **Git layer (the trap)**: the fix was already in the working tree, but
   deploy.sh builds `git+file:///home/mdupont/projects/system-manager?ref=main`.
   **Git flakes evaluate COMMITTED files only** — dirty working-tree edits are
   invisible to `nix build`. The build kept failing on the old committed
   `Environment = {...}` attrset.

**Diagnosis procedure:**
```bash
# 1. Get the exact failing option from the nix error trace:
#    "while evaluating the option `systemd.units.\"<svc>.service\".text'"
grep -n "Environment = {" /home/mdupont/projects/system-manager/all-services.nix
#    → any hit inside serviceConfig is the bug

# 2. Check whether the fix is COMMITTED (what the flake sees):
cd /home/mdupont/projects/system-manager
git show HEAD:all-services.nix | grep -n "Environment = {"
#    → non-empty = flake still builds the broken version → commit the fix

# 3. Check for other dirty files that the flake can't see:
git status --short   # any ' M ' file is invisible to git+file flakes
```

**Fix:**
```bash
cd /home/mdupont/projects/system-manager
git add all-services.nix flake.lock ipld-car-shmem.nix
git commit -m "fix(services): ..."
cd /mnt/data1/kant/pastebin && ./deploy.sh
```

**Prevention:** before deploying, run
`git -C /home/mdupont/projects/system-manager status --short` — if anything
is dirty, commit first or the deploy silently evaluates stale code.

### Case 2: stale flake input / old store path (EACCES)
If nix complains about a store path that no longer exists or EACCES on a
flake input: `nix flake update <input>` in system-manager, commit the
flake.lock, redeploy. (Seen 2026-09-23 with tracker-following-mitmp.)

### Case 3: "cargo build failed or timed out, but nix build succeeded"
WARNING only — deploy proceeds. Nora registry (localhost:4000) slow or the
120s timeout too short for cold builds. Not fatal.

## Deploy log location
`/mnt/data1/kant/pastebin/logs/deploy-<timestamp>.log` — always check the
tail for the nix error trace; the option name in the trace names the
exact broken service.
