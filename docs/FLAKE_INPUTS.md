# Flake inputs: real remotes, pinned revs, and nora for crates

Every input to `flake.nix` is a URL a GitHub runner can fetch. They were not,
and that is why the `Nix Build` check on `main` has been red since the Oct 1
merges. There were two separate faults.

## 1. `?ref=omain`

`flake.nix` had `?ref=omain` and `?ref=omaster`. Neither ref exists — only
`main` does — so every evaluation failed with

```
Cannot find Git revision '11707dc2…' in ref 'omain' of repository
'file:///mnt/data1/git/github.com/numtide/flake-utils.git'
```

The same truncated word in both, so it reads like a find/replace over
main/master rather than one typo made twice. Fixed in `f4ebe24f`.

## 2. `file:///mnt/data1/...`, which no runner has

The refs were only half the problem. Every input was a local path:

| was | now |
|---|---|
| `git+file:///mnt/data1/git/github.com/NixOS/nixpkgs.git?ref=nixos-unstable` | `github:NixOS/nixpkgs/0954f7ee…` |
| `git+file:///mnt/data1/git/github.com/numtide/flake-utils.git?ref=main` | `github:numtide/flake-utils/11707dc2…` |
| `path:/mnt/data1/time-2026/05-may/19/crane` | `github:ipetkov/crane/8833b7dc…` |
| `path:/mnt/data1/nora/storage/cargo` | *deleted* — see §3 |
| `git+file:///mnt/data1/git/github.com/numtide/system-manager.git?ref=main` | `github:numtide/system-manager/3dd7dbe…` |
| `path:./browser` | unchanged: it is in this repository |

A runner has no `/mnt/data1`, so the ref fix alone left CI red on the next
failure. `flake.lock` now contains **zero** `mnt/data1` references.

`crane` was a working tree at `/mnt/data1/time-2026/05-may/19/crane`, not a
URL. Its `local` remote points at `~/git/github.com/ipetkov/crane.git` and its
upstream is `https://github.com/ipetkov/crane`, so the commit it sat on
(`8833b7dc`, "cargoTomlConservative: hand construct the index (#1062)") is on
GitHub and can be named directly.

## 3. Crates come from nora over HTTPS, not from a local path

`nora-cargo` existed for one reason: to point `dl` at the crate tarballs on
disk.

```nix
dl = "file://${nora-cargo}/{crate}/{version}/{crate}-{version}.crate";
```

and then `overrideVendorCargoPackage` untarred them and wrote a
`.cargo-checksum.json` containing `{"files":{},"package":"<checksum>"}` — an
empty file list, which only worked because nothing was in a position to check
it.

Nora serves the same tarballs over HTTPS, so the input and the override are
both gone and cargo verifies the tarballs itself:

```nix
indexUrl = "https://solana.solfunmeme.com/nora/cargo/index/";
dl       = "https://solana.solfunmeme.com/nora/cargo/api/v1/crates/{crate}/{version}/download";
```

The `dl` template has to be given explicitly. The index's own `config.json`
advertises `dl: ".../api/v1/crates"`, and cargo's default
`{crate}/{version}/{crate}-{version}.crate` appended to that **404s**. The real
layout ends in `/download`. Verified:

```sh
curl -sO https://solana.solfunmeme.com/nora/cargo/api/v1/crates/float-cmp/0.10.0/download
sha256sum float-cmp-0.10.0.crate
# b09cf3155332e944990140d967ff5eceb70df778b34f77d8075db46e4704e6d8
# — which is the `cksum` the sparse index publishes for that version
```

## 4. Why every input is pinned by rev

A branch name here means any upstream commit silently changes what this builds.
That is not hypothetical: `?ref=omain` survived weeks because a ref is a string
that only fails when someone evaluates it.

It matters most for `system-manager`. Commit `3dd7dbe` is the one that vendored
its 107 crate dependencies — that `vendor/` directory is what lets the build
work without reaching crates.io, which returns 403 (see `~/gitplan.org`).
Tracking `main` would drift off the vendored commit and break the build, so
drifting is a regression here, not an upgrade.

**To bump one deliberately**, change the rev in `flake.nix`, run
`nix flake update <name>`, and read the diff in `flake.lock` — if it moves
another input too, that is transitive drift and wants its own review.

## 5. The local mirrors

`~/git/github.com/<owner>/<repo>.git` holds bare mirrors of these repos, and
gitplan.org's first rule is to look there before cloning anything. They are not
wired into the flake by a global `git config url.…insteadOf` rule, on purpose:
such a rule rewrites `https://github.com/` globally, which would also redirect
`git push` for every repository on this machine to a local path.

For an offline build, override the inputs explicitly instead:

```sh
nix build .#kant-pastebin \
  --override-input nixpkgs       git+file:///home/mdupont/git/github.com/NixOS/nixpkgs.git?ref=nixos-unstable \
  --override-input flake-utils   git+file:///home/mdupont/git/github.com/numtide/flake-utils.git?ref=main \
  --override-input system-manager git+file:///home/mdupont/git/github.com/numtide/system-manager.git?ref=main \
  --override-input crane         git+file:///home/mdupont/git/github.com/ipetkov/crane.git?rev=8833b7dc3c7426ce1110ed6fed31b6f63d74f2dc
```

Note the crane mirror is **behind** the pinned rev — its `master` is `59a82a1`
and it does not contain `8833b7dc`. Push it before relying on that override:

```sh
git -C /mnt/data1/time-2026/05-may/19/crane push local HEAD:refs/heads/master
```

## What CI still needs

Nothing is left in this flake that only exists on this machine. Two things can
still fail there, and neither is a flake problem:

* `systemConfigs` build and activate on a runner — the check runs `nix build`,
  which builds `packages.default`, not a system config.
* crates come from `https://solana.solfunmeme.com/nora/`, which is this host. If
  it is down or unreachable from the runner, the build cannot vendor.
