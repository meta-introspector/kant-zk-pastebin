# Task: pastebin-nix-ci-file-url-inputs

**Status:** open — **this is the only thing keeping upstream CI red**
**Project:** kant/pastebin (meta-introspector/kant-zk-pastebin)
**Found:** 2026-10-02

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
