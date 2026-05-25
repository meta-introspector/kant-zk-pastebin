{
  description = "Kant Pastebin - UUCP + zkTLS tile server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Git submodule bare mirrors — Nix does not recursively fetch nested
    # submodule content from src = ./., so we supply them as flake inputs.
    # Each points to a local bare mirror at the pinned submodule commit.

    html5ever-src = {
      url = "git+file:///mnt/data1/git/solana.solfunmeme.com/html5ever.git?rev=70a1b3a7568f7e302367dd4b2806cf2fd22758cc";
      flake = false;
    };

    rust-cssparser-src = {
      url = "git+file:///mnt/data1/git/solana.solfunmeme.com/rust-cssparser.git?rev=aae89a8330951e441e0010fdd1907be4cb119eb5";
      flake = false;
    };

    oxc-src = {
      url = "git+file:///mnt/data1/nix/time/2024/09/01/oxc/?rev=0fa6e540aa11d2026d8fcaacfe8381253ddcafd5&ref=cargo0.0.1";
      flake = false;
    };

    erdfa-canonical-src = {
      url = "git+file:///mnt/data1/git/solana.solfunmeme.com/erdfa-canonical.git?rev=6645fbbb3450ea142e461517cb170d74126310f1";
      flake = false;
    };

    zos-circuit-optimizer-src = {
      url = "git+file:///mnt/data1/git/solana.solfunmeme.com/zos-circuit-optimizer.git?rev=2d26e13f3399438095ae70bec40d81af65f3e014";
      flake = false;
    };

    zkperf-src = {
      url = "git+file:///home/mdupont/git/github.com/meta-introspector/zkperf.git?rev=4346b6e28b1ca4a6a51a30f2d386d09dd2638c33";
      flake = false;
    };

    erdfa-publish-src = {
      url = "git+file:///mnt/data1/git/solana.solfunmeme.com/erdfa-publish.git?rev=92f0bae8640c6defed0c6d2abc5e136e161c74d4";
      flake = false;
    };

    rust-ipfs-src = {
      url = "git+file:///home/mdupont/git/github.com/meta-introspector/rust-ipfs.git?rev=27adf822c10542f191696a1ce01091e08e84beb7";
      flake = false;
    };

    # crate2nix — Rust crate-level build tool that handles all crate types
    # (lib, bin, proc-macro), path deps, and vendor setup automatically.
    crate2nix = {
      url = "git+file:///mnt/data1/time-2026/04-april/26/crate2nix-zos/vendor/crate2nix?submodules=1";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay
            , html5ever-src, rust-cssparser-src, oxc-src
            , erdfa-canonical-src, zos-circuit-optimizer-src, zkperf-src
            , erdfa-publish-src, rust-ipfs-src
            , crate2nix
            }:
    # ── Load idea cloud module ──────────────────────────────────────────
    let
      inherit (nixpkgs) lib;
      loadIdeacloud = import ./ideacloud.nix;
      loadApply = import ./apply.nix;
      loadM1cr0 = import ./m1cr0.nix;
      ideacloud = loadIdeacloud;
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };

        # Nightly toolchain (needed for some deps like zkperf-macros proc-macros)
        rustToolchain = pkgs.rust-bin.nightly.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" "clippy" "rustfmt" ];
        };

        # ── Idea cloud scan (pure Nix) ──────────────────────────────────
        scanData = [
          { path = ".gitmodules"; content = builtins.readFile ./.gitmodules; }
          { path = "Cargo.toml";  content = builtins.readFile ./Cargo.toml; }
          { path = "flake.nix";   content = builtins.readFile ./flake.nix; }
        ] ++ lib.optional (builtins.pathExists ./plugins/html5ever/.gitmodules)
            { path = "plugins/html5ever/.gitmodules"; content = builtins.readFile ./plugins/html5ever/.gitmodules; }
          ++ lib.optional (builtins.pathExists ./plugins/html5ever/Cargo.toml)
            { path = "plugins/html5ever/Cargo.toml"; content = builtins.readFile ./plugins/html5ever/Cargo.toml; }
          ++ lib.optional (builtins.pathExists ./plugins/oxc/Cargo.toml)
            { path = "plugins/oxc/Cargo.toml"; content = builtins.readFile ./plugins/oxc/Cargo.toml; }
          ++ lib.optional (builtins.pathExists ./erdfa-canonical/bindings/rust/Cargo.toml)
            { path = "erdfa-canonical/bindings/rust/Cargo.toml"; content = builtins.readFile ./erdfa-canonical/bindings/rust/Cargo.toml; };

        applyResult = loadApply { inherit lib ideacloud; scan = scanData; };

        # ── Combined source: main repo + all submodule contents ─────────
        combinedSrc = pkgs.runCommand "kant-pastebin-src" {
          # Pass Cargo.lock as an explicit input so working-tree changes
          # invalidate the derivation hash.
          cargoLock = ./Cargo.lock;
        } ''
          cp -a --no-preserve=mode ${self.outPath} $out
          chmod -R u+w $out

          # Replace stale Cargo.lock with current working tree version
          cp "$cargoLock" $out/Cargo.lock

          # Replace empty submodule dirs with bare mirror content
          rm -rf $out/plugins/html5ever
          mkdir -p $out/plugins
          cp -a --no-preserve=mode ${html5ever-src} $out/plugins/html5ever

          rm -rf $out/plugins/html5ever/cssparser
          cp -a --no-preserve=mode ${rust-cssparser-src} $out/plugins/html5ever/cssparser

          rm -rf $out/plugins/oxc
          cp -a --no-preserve=mode ${oxc-src} $out/plugins/oxc

          rm -rf $out/plugins/zos-circuit-optimizer
          cp -a --no-preserve=mode ${zos-circuit-optimizer-src} $out/plugins/zos-circuit-optimizer

          rm -rf $out/erdfa-canonical
          cp -a --no-preserve=mode ${erdfa-canonical-src} $out/erdfa-canonical

          rm -rf $out/zkperf
          cp -a --no-preserve=mode ${zkperf-src} $out/zkperf

          # zkperf workspace expects erdfa-publish as a sibling
          rm -rf $out/zkperf/erdfa-publish
          ln -s $out/erdfa-canonical/bindings/rust $out/zkperf/erdfa-publish

          rm -rf $out/erdfa-canonical/bindings/rust
          mkdir -p $out/erdfa-canonical/bindings
          cp -a --no-preserve=mode ${erdfa-publish-src} $out/erdfa-canonical/bindings/rust

          rm -rf $out/erdfa-canonical/bindings/rust/vendor/rust-ipfs
          mkdir -p $out/erdfa-canonical/bindings/rust/vendor
          cp -a --no-preserve=mode ${rust-ipfs-src} $out/erdfa-canonical/bindings/rust/vendor/rust-ipfs
        '';

        # ── crate2nix build ─────────────────────────────────────────────
        tools = import "${crate2nix}/tools.nix" { inherit pkgs; };

        # Custom rustc via buildRustCrate.override, plus per-crate cargo
        # commands via defaultCrateOverrides.
        buildRustCrateForPkgs = p: p.buildRustCrate.override {
          rustc = rustToolchain;
          defaultCrateOverrides = p.defaultCrateOverrides // {
            # Allow workspace-level patching if needed
            kant-pastebin = attrs: {
              preBuild = "echo Building kant-pastebin workspace";
            };
          };
        };

        # Generate Cargo.nix from the combined source + Cargo.lock
        cargoNix = import (tools.generatedCargoNix {
          name = "kant-pastebin";
          src = combinedSrc;
          cargo = rustToolchain;
        }) {
          inherit pkgs buildRustCrateForPkgs;
        };

      in {
        packages = {
          # Main build: uses crate2nix for proper handling of all crate types
          default = cargoNix.rootCrate.build;

          # Ideacloud reverse index as JSON
          ideacloud-scan = pkgs.runCommand "ideacloud-scan.json" { } ''
            cat > $out << EOF
            ${builtins.toJSON applyResult.reverseIndex}
            EOF
          '';
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [ rustToolchain pkgs.pkg-config pkgs.openssl pkgs.openssl.dev ];
          PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
          shellHook = ''
            echo "Kant Pastebin dev shell (crate2nix)"
            echo "  nix build   — Build via crate2nix"
            echo "  cargo build — Direct build"
          '';
        };
      }
    ) // {

    # ── Top-level lib outputs (pure Nix values, shared across flakes) ───
    lib = {
      inherit ideacloud;
      apply = loadApply;
      m1cr0 = loadM1cr0;
      ideas = ideacloud.ideas;
      topos = ideacloud.topoSort nixpkgs.lib;
    };
  };
}
