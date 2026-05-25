# m1cr0.nix — Microflake: turn a single artifact into a minimal Nix output
#
# Usage:
#   mkMicroflake pkgs { path = "/nix/store/..."; name = "my-file"; }
#   mkMicroflake pkgs { path = "/some/path"; name = "my-file"; sha256 = "..."; }
#
# Two modes:
#   1. Pure reference (no sha256): symlink to an existing store path
#   2. Fixed-output (with sha256): content-addressed import

{ pkgs }:

artifact:
let
  path = artifact.path or (throw "m1cr0: path required");
  name = artifact.name or (builtins.baseNameOf path);
  sha256 = artifact.sha256 or null;
in
if sha256 == null then
  # Pure reference — just symlink to existing store path
  # No re-import, no copying, instant
  pkgs.runCommand name { } ''
    mkdir -p "$out"
    ln -s ${path} "$out/${name}"
  ''
else
  # Fixed-output content-addressed derivation
  pkgs.stdenv.mkDerivation {
    pname = name;
    version = "m1";
    src = pkgs.fetchurl {
      url = "file://${path}";
      inherit sha256;
    };
    dontUnpack = true;
    installPhase = ''
      mkdir -p "$out"
      cp "$src" "$out/${name}"
    '';
  }
