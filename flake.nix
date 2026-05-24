{
  description = "Kant Pastebin - UUCP + zkTLS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Shared inputs — all common git repos declared centrally
    common-inputs = {
      url = "path:/home/mdupont/nix-common";
    };

    # Cargo2nix for vendored dependencies
    cargo2nix.url = "github:cargo2nix/cargo2nix";

    # Pastebin submodules (not in shared flake or different refs)
    erdfa-canonical-local = { url = "path:/mnt/data1/kant/pastebin/erdfa-canonical"; flake = false; };
    erdfa-clean-local = { url = "path:/mnt/data1/kant/pastebin/erdfa-clean"; flake = false; };
    html5ever-local = { url = "path:/mnt/data1/kant/pastebin/plugins/html5ever"; flake = false; };
    oxc-local = { url = "path:/mnt/data1/kant/pastebin/plugins/oxc"; flake = false; };
    zos-circuit-local = { url = "path:/mnt/data1/kant/pastebin/plugins/zos-circuit-optimizer"; flake = false; };
    zkperf-local = { url = "path:/mnt/data1/kant/pastebin/zkperf"; flake = false; };

    # Other local plugins (not submodules)
    erdfa-dasl = { url = "path:/mnt/data1/kant/pastebin/plugins/erdfa-dasl"; flake = false; };
    erdfa-sheaf = { url = "path:/mnt/data1/kant/pastebin/plugins/erdfa-sheaf"; flake = false; };
    zos-pastebin = { url = "path:/mnt/data1/kant/pastebin/plugins/zos-pastebin"; flake = false; };
  };

  outputs = { self, nixpkgs, common-inputs, cargo2nix,
    erdfa-canonical-local, erdfa-clean-local,
    html5ever-local, oxc-local, zos-circuit-local, zkperf-local,
    erdfa-dasl, erdfa-sheaf, zos-pastebin }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      inherit (common-inputs) rust-ipfs erdfa-publish;
      cargo2nixPkgs = cargo2nix.packages.x86_64-linux;

      # Import vendored crate configurations
      vendoredCrates = builtins.listToAttrs (map (crateName: {
        name = crateName;
        value = import ./vendor-cargo2nix/${crateName}.nix {
          mkRustCrate = cargo2nixPkgs.mkRustCrate;
          fetchFromGitHub = pkgs.fetchFromGitHub;
          lib = pkgs.lib;
        };
      }) (builtins.attrNames (builtins.readDir ./vendor-cargo2nix)));

      makePatchedSrc = pkgs: pkgs.runCommand "kant-pastebin-src" {} ''
        # Copy root level files, excluding .git and target
        mkdir -p $out
        for item in ${self}/*; do
          base=$(basename "$item")
          if [ "$base" != ".git" ] && [ "$base" != "target" ]; then
            cp -r --no-preserve=mode "$item" "$out/$base"
            chmod -R u+w "$out/$base"
          fi
        done

        # Submodules (not tracked in git tree)
        rm -rf $out/erdfa-canonical
        cp -r --no-preserve=mode ${erdfa-canonical-local} $out/erdfa-canonical
        find $out/erdfa-canonical -name target -type d -exec rm -rf {} + 2>/dev/null || true
        chmod -R u+w $out/erdfa-canonical
        rm -rf $out/erdfa-clean
        cp -r --no-preserve=mode ${erdfa-clean-local} $out/erdfa-clean
        chmod -R u+w $out/erdfa-clean
        rm -rf $out/plugins/html5ever
        cp -r --no-preserve=mode ${html5ever-local} $out/plugins/html5ever
        find $out/plugins/html5ever -name target -type d -exec rm -rf {} + 2>/dev/null || true
        chmod -R u+w $out/plugins/html5ever
        rm -rf $out/plugins/oxc
        cp -r --no-preserve=mode ${oxc-local} $out/plugins/oxc
        find $out/plugins/oxc -name target -type d -exec rm -rf {} + 2>/dev/null || true
        chmod -R u+w $out/plugins/oxc
        rm -rf $out/plugins/zos-circuit-optimizer
        cp -r --no-preserve=mode ${zos-circuit-local} $out/plugins/zos-circuit-optimizer
        chmod -R u+w $out/plugins/zos-circuit-optimizer
        rm -rf $out/zkperf
        cp -r --no-preserve=mode ${zkperf-local} $out/zkperf
        find $out/zkperf -name target -type d -exec rm -rf {} + 2>/dev/null || true
        chmod -R u+w $out/zkperf

        # Shared deps injected into submodule trees
        ln -s ${erdfa-publish} $out/erdfa-canonical/bindings/rust
        ln -s ${rust-ipfs}   $out/erdfa-canonical/bindings/rust/vendor/rust-ipfs

        # Non-submodule plugins
        ln -s ${erdfa-dasl}   $out/plugins/erdfa-dasl
        ln -s ${erdfa-sheaf}  $out/plugins/erdfa-sheaf
        ln -s ${zos-pastebin} $out/plugins/zos-pastebin
      '';
    in
    {
      packages = nixpkgs.lib.genAttrs systems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in {
          # Legacy build (original)
          default = pkgs.rustPlatform.buildRustPackage {
            pname = "kant-pastebin";
            version = "0.1.0";
            src = makePatchedSrc pkgs;
            cargoVendorDir = "${self}/vendor";
            nativeBuildInputs = [ pkgs.pkg-config pkgs.wasm-pack pkasg.git ];
            buildInputs = [ pkgs.openssl ];
          };

          # DAG-CBOR spec tiles (built from dasl-testing coverage sheaf)
          dagcbor-tiles = pkgs.stdenvNoCC.mkDerivation {
            name = "dagcbor-tiles";
            src = /mnt/data1/time-2026/02-february/22/dasl/dasl-testing/sheaf/tiles;
            dontBuild = true;
            installPhase = ''
              mkdir -p $out
              cp dagcbor_tiles.html $out/
            '';
          };

          # New cargo2nix build with vendored dependencies
          kant-pastebin-cargo2nix = cargo2nixPkgs.mkRustCrate {
            name = "kant-pastebin";
            version = "0.1.0";
            src = makePatchedSrc pkgs;
            buildInputs = [ pkgs.openssl ];
            dependencies = {
              inherit (vendoredCrates) serde tokio actix-web clap;
            };
          };

          # Vendored crates individually
          vendored-crates = vendoredCrates;
        }
      );

      devShells = nixpkgs.lib.genAttrs systems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [ 
              cargo2nixPkgs.cargo
              cargo2nixPkgs.rustc
              cargo rustc rust-analyzer rustfmt clippy pkg-config openssl nodejs chromium wasm-pack cargo-audit
            ];
            shellHook = ''
              echo "Kant Pastebin Development Environment"
              echo "Vendored crates: $(ls vendor-cargo2nix/ | wc -l) crates"
              echo "Available commands:"
              echo "  cargo build          - Build the project"
              echo "  cargo test          - Run tests"
              echo "  cargo check         - Check for errors"
              echo "  cargo audit         - Security audit"
              echo "  nix develop         - Enter development shell"
            '';
          };
        }
      );

      # Vendored crates flake
      vendored = import ./flake-vendor-unified.nix;

      formatter = nixpkgs.lib.genAttrs systems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
