# Next Steps Plan

## Goal
Get `deploy.sh deploy` working end-to-end (Nix build → system-manager activation → pastebin serving new binary).

## Current blockers
1. `flake.nix` is broken — crane API mismatch between local checkout and HEAD version
2. `nix build` fails at evaluation because `cargoBuild` requires `cargoArtifacts` argument
3. Even if syntax passes, build will fail on `sparse+https://solana.solfunmeme.com/nora/cargo/index/` unless we use the `[patch.crates-io]` workaround in `.cargo/config.toml`

## Steps

1. **Restore `flake.nix` to HEAD exactly** (`git show HEAD:flake.nix`) — it already had the working `buildDepsOnly` + `buildPackage` + `vendorCargoDeps` + `overrideVendorCargoPackage` + `noraCargoPackage` pattern. Do not edit it further.

2. **Verify `.cargo/config.toml`** has the `[patch.crates-io]` workaround (already written). This makes crane treat nora crates as local patches instead of remote sparse registry crates.

3. **Run `nix build .#kant-pastebin`** and capture the actual error. If it's the sparse registry error, the patch config should fix it. If it's something else, diagnose from the real error.

4. **If build succeeds**: Run `deploy.sh deploy` to activate via system-manager.

5. **If build still fails**: Try the old local crane checkout (`/mnt/data1/time-2026/05-may/19/crane`) with the `vendorCargoDeps` + `cargoBuild` API that matches that checkout.

6. **Final verification**: Check pastebin serves the new binary at `http://127.0.0.1:8090/gallery` and the SVG/GIF fixes are live.
