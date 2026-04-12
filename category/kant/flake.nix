{
  description = "Kant Pastebin - Build from bare repositories and feature branches";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        pastebin-main-src = builtins.fetchGit {
          url = "file:///mnt/data1/git/github.com/meta-introspector/kant-zk-pastebin";
          rev = "b2f5cd8d5ae23398d6c5d08c10451fcfb914cc0c"; # UPDATED REV
        };

        erdfa-publish-src = builtins.fetchGit {
          url = "/mnt/data1/git/solana.solfunmeme.com/erdfa-publish.git";
          rev = "360a043ac9bbb12c947587af07929d695926eed6";
        };

        erdfa-canonical-src = builtins.fetchGit {
          url = "/home/mdupont/git/solana.solfunmeme.com/erdfa-canonical.git";
          rev = "6f8b33d527081a7d780b9a177cb49997a4e12bec";
        };

        rust-ipfs-src = builtins.fetchGit {
          url = "file:///home/mdupont/git/github/dariusc93/rust-ipfs.git";
          rev = "4eeb9403889941c4453d81ad66ace7a595c1e152";
        };

        # Build a patched source tree with all components injected
        patchedSrc = pkgs.runCommand "kant-pastebin-src" {} ''
          cp -r --no-preserve=mode ${pastebin-main-src}/. $out
          chmod -R u+w $out
          


          # Inject erdfa-canonical first
          rm -rf $out/erdfa-canonical
          cp -r --no-preserve=mode ${erdfa-canonical-src}/. $out/erdfa-canonical

          # Then inject erdfa-publish over erdfa-canonical/bindings/rust
          # This assumes erdfa-publish-src *is* the content for bindings/rust
          mkdir -p $out/erdfa-canonical/bindings/ # Ensure parent directory exists for safety
          rm -rf $out/erdfa-canonical/bindings/rust # Clean up existing directory within erdfa-canonical
          cp -r --no-preserve=mode ${erdfa-publish-src}/. $out/erdfa-canonical/bindings/rust





          # Inject rust-ipfs
          mkdir -p $out/erdfa-canonical/bindings/rust/vendor/ # Ensure parent directories exist
          rm -rf $out/erdfa-canonical/bindings/rust/vendor/rust-ipfs # Clean up target
          cp -r --no-preserve=mode ${rust-ipfs-src}/. $out/erdfa-canonical/bindings/rust/vendor/rust-ipfs








          # The original pastebin flake.nix had postPatch:
          # (cd pastebin-wasm && wasm-pack build --target web --out-dir ./static/pkg)
          # pastebin-wasm is part of pastebin-main-src, so this should still work.
        '';
      in
      {
        packages = {
          kant-pastebin = pkgs.rustPlatform.buildRustPackage {
            pname = "kant-pastebin-from-bare";
            version = "0.1.0";
            src = patchedSrc;
            cargoLock.lockFile = pastebin-main-src + "/Cargo.lock"; # Use Cargo.lock from pastebin-main-src

            nativeBuildInputs = [ pkgs.pkg-config pkgs.wasm-pack pkgs.git ];
            buildInputs = [ pkgs.openssl ];

            postPatch = ''
              # No git submodule update needed as sources are injected
              (cd pastebin-wasm && wasm-pack build --target web --out-dir ./static/pkg)
            '';
          };
          default = self.packages.${system}.kant-pastebin;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            cargo
            rustc
            rust-analyzer
            rustfmt
            clippy
            pkg-config
            openssl
            nodejs
            chromium
            wasm-pack
          ];
          shellHook = ''
            export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1
            export PUPPETEER_EXECUTABLE_PATH=${pkgs.chromium}/bin/chromium
          '';
        };
      }
    );
}
