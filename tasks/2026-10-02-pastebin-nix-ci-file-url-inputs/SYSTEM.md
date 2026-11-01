# Task: pastebin-nix-ci-file-url-inputs

**Status:** the input half is fixed; the blocker moved to the nora registry
**Project:** kant/pastebin (meta-introspector/kant-zk-pastebin)
**Found:** 2026-10-02
**Updated:** 2026-11-01

## Problem

The `Nix Build` check on `main` has been red since the Oct 1 merges:

```
Cannot find Git revision '11707dc2…' in ref 'omain'
```

Two independent causes, one fixed and one not.

**Fixed** (`f4ebe24f`, `4b45d79e` in PR #6): `flake.nix` had `?ref=omain` and
`?ref=omaster`. Neither ref exists in the mirrors — only `main` — so every nix
evaluation failed. The same truncated word in both reads like a find/replace
over main/master rather than one typo made twice.

**Not fixed, and it is the one that matters.** The inputs are still local paths:

```
nixpkgs.url  = "git+file:///mnt/data1/git/github.com/NixOS/nixpkgs.git?ref=nixos-unstable"
crane.url    = "path:/mnt/data1/time-2026/05-may/19/crane"
nora-cargo   = "path:/mnt/data1/nora/storage/cargo"
```

A GitHub runner has no `/mnt/data1`. It cannot resolve any of these, so the
check stays red after the ref fix.

## Fix

Point every input at a real remote that a runner can fetch:

| input | now | needs |
|---|---|---|
| `nixpkgs` | `file:///mnt/data1/git/.../nixpkgs` | `github:NixOS/nixpkgs/nixos-unstable` |
| `flake-utils` | `file:///mnt/data1/git/.../flake-utils` | `github:numtide/flake-utils` |
| `system-manager` | `file:///mnt/data1/git/.../system-manager` | `github:numtide/system-manager` |
| `crane` | `path:/mnt/data1/time-2026/.../crane` | a remote, or vendor it |
| `nora-cargo` | `path:/mnt/data1/nora/storage/cargo` | a registry or a checked-in vendor dir |

`crane` and `nora-cargo` are the hard ones — they are local directories, not
repos, so they need vendoring or publishing before CI can build at all.

Also note `browser/` must be a directory and git-tracked for the `path:`
input to copy it, and that `jmikedupont2/` and `mdupont/` are not GitHub
accounts, so any input that assumed they were will fail to authenticate.

## Verify

```sh
# from a clean clone of the repo, on a machine with no /mnt/data1
nix flake check
```

Then re-run the `Nix Build` check on the PR.

## Update (2026-11-01)

**The input half of this task is done.** `345269df` ("build: make every
flake input something a runner can fetch") replaced every `file:///mnt/data1/...`
mirror with a `github:` remote pinned by rev:

| input | now |
|---|---|
| `nixpkgs` | `github:NixOS/nixpkgs/0954f7ee…` |
| `flake-utils` | `github:numtide/flake-utils/11707dc2…` |
| `crane` | `github:ipetkov/crane/8833b7dc…` |
| `system-manager` | `github:numtide/system-manager/3dd7dbe5…` |

The `?ref=omain` typo is gone with it, and `docs/FLAKE_INPUTS.md` records the
before/after table and how to bump an input. The `Cannot find Git revision
'11707dc2…' in ref 'omain'` error no longer appears anywhere.

**The blocker is now the nora registry, and it is not a flake-input problem.**
The crates that are not on crates.io — `rust-unixfs`, `ipld-dagpb`,
`quick-protobuf`, `erdfa-publish` — come from nora, over HTTPS, at

    indexUrl = "https://solana.solfunmeme.com/nora/cargo/index/"

That URL works. From this machine it answers `HTTP 200` for
`ru/st/rust-unixfs` in a few hundred milliseconds, and the registry's
`config.json` is well-formed.

It does not work from a GitHub runner, and the reason is not the flake:

    $ getent hosts solana.solfunmeme.com
    192.168.68.62   solana.solfunmeme.com
    127.0.0.1       solana.solfunmeme.com

**The host is a LAN address.** `192.168.68.62` is a private address on the
local network, and a GitHub Actions runner has no route to it. The failure
says exactly that, once the timeout is long enough to give up:

    curl: (28) Failed to connect to solana.solfunmeme.com:443 after 132866 ms
    error: cannot download cargo-src-cc-1.2.63 from any mirror
    error: 1 dependencies of derivation '…-vendor-registry.drv' failed to build

So the nora registry is reachable only from inside the network. Any flake
input that points at it has the same problem, and no amount of editing
`flake.nix` will change that — the URL is a LAN address.

### What this needs, and the options

The build needs those four crates to come from somewhere a runner can reach.

1. **Publish them to crates.io.** Then `registry = "nora"` in `Cargo.toml`
   goes away and the problem ends. This is the clean answer, and it is not
   a code change.
2. **Vendor them into the repository**, the way `system-manager` already
   carries a `vendor/` directory so that it builds without crates.io. The
   four crates are small and their transitive dependencies are on crates.io.
   This is the in-house precedent, and it is what `flake.nix`'s own comment
   points at: *"system-manager … carries a vendored `vendor/` directory that
   is what makes the build work without crates.io"*.
3. **Put the registry at a public address** and point `indexUrl` there.

Until one of those happens, `Nix Build` stays red on every branch, and
`main` included.

### The other red check is unrelated

`Build and Push Docker Image` fails with `Username and password required`.
That is not the registry and not the nix inputs: the workflow logs in with
`secrets.DOCKER_HUB_TOKEN`, and **this repository has no such secret**. The
only secret it has is `KANT_CI_SECRET`; `gh secret list` shows nothing else,
and the org's secrets are not visible from here.

`build-feed.yml` already handles this case the right way — it checks for
its own two secrets and skips the notification when they are absent, so the
build result is unaffected. `docker-build.yml` should do the same: build the
image always, push it only when the token is there. See the
`chore/ci-docker-push-optional` branch.

