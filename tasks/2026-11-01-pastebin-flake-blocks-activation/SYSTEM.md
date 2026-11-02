# Task: Unblock `pastebin-src` so `all-services` can activate

**Status:** OPEN — blocked upstream, in the pastebin repo
**Owner:** agent
**Area:** Nix / system-manager activation
**Priority:** P0 (blocks `system-manager switch` on this host)

## What was asked

Deploy the host config (`sm-deploy` → `system-manager switch`) so that
`kagenti-daemon.service` and the rest of `all-services` are installed. The
activation fails, and it is not kagenti's fault: the config needs
`pastebin-src.packages.x86_64-linux.kant-pastebin`, and **no pastebin commit
builds right now**.

## Root cause (measured, 2026-11-01)

Two independent defects in `/mnt/data1/kant/pastebin`, one per rev:

| rev | defect | error |
|---|---|---|
| `5c4e6451` (`feature/big-merge`, what `system-manager/flake.lock` pins) | its lock pins a **mutable local cargo registry** (`nora-cargo`) at a `path:` under `/mnt/data1/nora/storage/cargo`; the dir changes as cargo fetches, so the recorded `narHash` drifts | `NAR hash mismatch in input 'pastebin-src/nora-cargo'` |
| branch head | drops `nora-cargo` entirely, but the `[registries.nora]` table the build needs lives only in an **uncommitted** working-tree config | `registry index was not found in any configuration: nora` |

Nix rejects the obvious workaround: an `inputs.pastebin-src.inputs.nora-cargo`
override in *our* flake answers `override for a non-existent input` for the
head (the input is gone) and is validated against the stale lock before it can
replace the drifting node.

Tried and reverted (recorded so it is not re-tried blindly):

1. advancing `pastebin-src` to the branch head — build breaks on the missing
   registry table;
2. a `path:/mnt/data1/kant/pastebin` input — `nix flake lock` spent >15 min
   hashing the tree (working-tree `.git` + vendor dirs) and was killed;
3. hand-inserting the override node into `flake.lock` — Nix erases/pins it back
   on the next update;
4. `nix flake update pastebin-src --override-input ...` in both the
   `inputs.pastebin-src.inputs.NAME` and `follows` spellings — both refused.

The only lock edit that survived and is kept: `tracker-merge`'s stale
`narHash` on `nixpkgs` (that one was genuinely out of date).

## Fix options, in order of preference

1. **In the pastebin repo (correct).** Make its flake build from a commit with
   no local registry: either declare `[registries.nora]` + the crane
   `appendCrateRegistries` entries in committed files (both are already written
   in `flake.nix` at the head), and commit the missing `.cargo/config.toml` or
   generate it inside the derivation; then `nix flake update pastebin-src` here.
2. **Pin the working tree.** `pastebin-src.url = "path:/mnt/data1/kant/pastebin"`.
   Unblocks immediately but hashes a directory that changes under it — needs
   `--impure` and re-locks on every local edit. Acceptable only as a stopgap.
3. **Drop pastebin from `all-services` for this activation**, deploy, then
   restore. Makes `kant-pastebin.service` temporarily absent from the host.

## Acceptance criteria

- [ ] `nix build .#packages.x86_64-linux.kant-pastebin` succeeds from a
      **committed** pastebin rev (no `--impure`, no local path input)
- [ ] `system-manager/flake.lock` pins that rev; `nix flake check` clean
- [ ] `nix build --impure .#packages.x86_64-linux.pipelight` reachable (it is
      the pinned 0.1.0 build; `deploy.sh` requires `--attach` on it)
- [ ] `system-manager switch` completes: `/etc/systemd/system/kagenti-daemon.service`
      exists as a symlink into the store
- [ ] `curl -s localhost:8480/apis/kagenti/v1/namespaces` → `{"namespaces":["default"]}`
- [ ] `systemctl is-active kagenti-daemon.service` → `active`

## Probes

```bash
# which rev are we pinned to, and which rev is the branch?
python3 -c "import json;n=json.load(open('/home/mdupont/projects/system-manager/flake.lock'))['nodes']['pastebin-src'];print(n['locked']['rev'],n['original'].get('ref'))"
git -C /mnt/data1/kant/pastebin log --oneline -1

# does the upstream flake still name a local registry?
grep -n 'path:/mnt/data1\|nora-cargo\|registries.nora' /mnt/data1/kant/pastebin/flake.nix

# the failing build, with its real message
cd /home/mdupont/projects/system-manager
nix build --impure --no-link --print-out-paths .#packages.x86_64-linux.pastebin 2>&1 | tail -30
```

## Notes

- The pastebin repo is being committed to concurrently by another agent
  (HEAD moved from `3207631` to `362f04dd` while this task was written), so
  re-read `flake.nix`/`flake.lock` there before pinning anything.
- `system-manager/flake.nix` carries a comment block recording this blocker at
  the `pastebin-src` input, so the next reader does not repeat the four
  reverted experiments.

## Related

- `~/DOCS/KAGENTI-NATIVE.md` §11 — host integration status
- `skills/system-manager-kagenti-native/SKILL.md` — the pin/build/deploy pattern and its failure modes
