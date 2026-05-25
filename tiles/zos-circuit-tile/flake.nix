{
  description = "zos-circuit-tile — standalone .so plugin for ZOS circuit rendering";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Bare mirror inputs for internal crate dependencies
    zos-circuit-optimizer-src = {
      url = "git+file:///mnt/data1/git/solana.solfunmeme.com/zos-circuit-optimizer.git?rev=3f66f4d096788869abc18d7bc5c79cb6669a93f8";
      flake = false;
    };
    erdfa-dasl-src = {
      url = "git+file:///home/mdupont/git/github.com/meta-introspector/erdfa-dasl.git?rev=1aa2574e94b0869b1f4c4592e89f9bca9cb1a95e";
      flake = false;
    };
    zkperf-src = {
      url = "git+file:///home/mdupont/git/github.com/meta-introspector/zkperf.git?rev=4346b6e28b1ca4a6a51a30f2d386d09dd2638c33";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay
            , zos-circuit-optimizer-src, erdfa-dasl-src, zkperf-src
            }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };

        # ── Combined source: tile at root + deps under deps/ ────────────
        #
        # Directory structure:
        #   $out/
        #     Cargo.toml          — tile crate (package name = zos-circuit-tile)
        #     Cargo.lock          — workspace lockfile
        #     src/lib.rs          — tile source code
        #     deps/
        #       zos-circuit-optimizer/  — git bare mirror content
        #       erdfa-dasl/             — git bare mirror content (Cargo.toml patched)
        #       zkperf-macros/          — from zkperf-src
        #       zkperf-witness/         — from zkperf-src
        #
        combinedSrc = pkgs.runCommand "zos-circuit-tile-src" { } ''
          set -euo pipefail

          # $out must be created explicitly in runCommand
          mkdir -p $out $out/src $out/deps

          # Place the tile Cargo.toml and source at $out root
          cp -a --no-preserve=mode ${./Cargo.toml} $out/Cargo.toml
          cp -a --no-preserve=mode ${./src/lib.rs} $out/src/lib.rs

          # Copy dep sources under $out/deps/
          cp -a --no-preserve=mode ${zos-circuit-optimizer-src} $out/deps/zos-circuit-optimizer
          cp -a --no-preserve=mode ${erdfa-dasl-src} $out/deps/erdfa-dasl
          cp -a --no-preserve=mode ${zkperf-src}/zkperf-macros $out/deps/zkperf-macros
          cp -a --no-preserve=mode ${zkperf-src}/zkperf-witness $out/deps/zkperf-witness

          # Patch all ../../zkperf/ references to ../zkperf-*
          for f in $out/deps/*/Cargo.toml; do
            sed -i 's|path = "../../zkperf/zkperf-macros"|path = "../zkperf-macros"|g' "$f"
            sed -i 's|path = "../../zkperf/zkperf-witness"|path = "../zkperf-witness"|g' "$f"
          done

          # Copy Cargo.lock
          cp -a --no-preserve=mode ${./Cargo.lock} $out/Cargo.lock

          echo "=== Combined source structure ==="
          find $out -name "Cargo.toml" | sort
        '';
      in
      {
        packages.default = pkgs.rustPlatform.buildRustPackage {
          pname = "zos-circuit-tile";
          version = "0.1.0";
          src = combinedSrc;
          cargoLock.lockFile = ./Cargo.lock;
          nativeBuildInputs = [ pkgs.pkg-config ];
          doCheck = false;
          installPhase = ''
            mkdir -p $out/lib $out/bin
            find target -name "*.so" -exec cp {} $out/lib/ \;
            find target -name "*.rlib" -exec cp {} $out/lib/ \;
            echo "=== Tile output ==="
            ls -la $out/lib/
          '';
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [ pkgs.rust-bin.stable.latest.default pkgs.pkg-config ];
        };
      }
    );
}
