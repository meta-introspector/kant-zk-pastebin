{
  description = "Kant Pastebin - UUCP + zkTLS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Shared inputs — all git repos declared centrally in ~/nix-common
    common-inputs = {
      url = "path:/home/mdupont/nix-common";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zos-circuit-tile = { url = "path:./tiles/zos-circuit-tile"; };
    org-tile = { url = "path:./tiles/org-tile"; };

    crate-vendor = {
      url = "git+file:///mnt/data1/git/flat/crate-vendor.git?ref=main-clean";
      flake = false;
    };

    kellnr = {
      url = "git+file:///mnt/data1/git/github.com/kellnr/kellnr.git";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    system-manager = {
      url = "git+file:///mnt/data1/git/github.com/numtide/system-manager.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pipelight = {
      url = "path:/mnt/data1/nix-controller/he-lattice/pipelight";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nora = {
      url = "path:/mnt/data1/time-2026/05-may/28/nora";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, common-inputs, system-manager, pipelight, crate-vendor, zos-circuit-tile, org-tile, kellnr, nora }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Pull shared inputs from the common flake (non-flake sources for path deps)
        # Assemble source tree: the Cargo.toml references path = "rust-ipfs/unixfs"
        # and path = "erdfa-publish", so both must exist at the root.
        kant-pastebin = pkgs.rustPlatform.buildRustPackage {
          pname = "kant-pastebin";
          version = "0.1.0";

          src = pkgs.runCommand "kant-pastebin-src" {
            # Pass store paths with safe env var names (underscores, not dashes)
            _rust_ipfs = common-inputs.inputs.rust-ipfs;
            _erdfa_publish = common-inputs.inputs.erdfa-publish;
            # crate-vendor passed as _crate_vendor (dash invalid in shell)
            _crate_vendor = crate-vendor;
            preferLocalBuild = true;
            allowSubstitutes = false;
          } ''
            cp -r ${self} $out
            chmod -R u+w $out
            rm -rf $out/erdfa-publish $out/rust-ipfs $out/result $out/result-1 $out/node_modules 2>/dev/null || true
            cp -r $(printenv _rust_ipfs) $out/rust-ipfs
            cp -r $(printenv _erdfa_publish) $out/erdfa-publish
            cp -r $(printenv _crate_vendor) $out/vendor
            chmod -R u+w $out/rust-ipfs $out/erdfa-publish $out/vendor
          '';

          cargoVendorDir = "vendor";

          nativeBuildInputs = with pkgs; [ pkg-config ];
          buildInputs = with pkgs; [ openssl ];

          # Enrich pipeline: tell the binary where tiles live
          TILES_DIR = "${zos-circuit-tile.packages.${system}.default}/lib:${org-tile.packages.${system}.default}/lib";

          doCheck = false;

          meta = with pkgs.lib; {
            description = "Kant Pastebin — UUCP + zkTLS with IPFS";
            license = licenses.mit;
            platforms = platforms.linux;
          };
        };

        index-docs = pkgs.writeShellScriptBin "kant-index-docs" ''
          PASTEBIN_URL="http://127.0.0.1:8090/paste"
          DOCS_DIR="$HOME/DOCS"
          SPOOL_DIR="$HOME/spool"

          index_file() {
              local file="$1"
              local title=$(basename "$file")
              local size=$(stat -c%s "$file" 2>/dev/null || echo 0)
              if [ "$size" -gt 1048576 ]; then return; fi
              local content=$(cat "$file" 2>/dev/null || echo "")
              if [ -z "$content" ] || [ ''${#content} -lt 10 ]; then return; fi
              local keywords=$(echo "$title" | tr '._-' '\n' | grep -E '^[a-zA-Z0-9]+$' | sort -u | head -10 | ${pkgs.jq}/bin/jq -R . | ${pkgs.jq}/bin/jq -s .)
              echo "Indexing: $title"
              local payload=$(${pkgs.jq}/bin/jq -n --arg t "$title" --arg c "$content" --argjson k "$keywords" '{title:$t,content:$c,keywords:$k}')
              ${pkgs.curl}/bin/curl -s -X POST "$PASTEBIN_URL" -H "Content-Type: application/json" -d "$payload" | ${pkgs.jq}/bin/jq -r '.id // empty'
          }

          echo "Indexing ~/DOCS..."
          ${pkgs.findutils}/bin/find "$DOCS_DIR" -type f \( -name "*.md" -o -name "*.txt" -o -name "*.org" \) 2>/dev/null | while read f; do
              index_file "$f"
          done

          echo "Indexing ~/spool..."
          ${pkgs.findutils}/bin/find "$SPOOL_DIR" -maxdepth 2 -type f \( -name "*.md" -o -name "*.txt" \) 2>/dev/null | head -30 | while read f; do
              index_file "$f"
          done

          echo "Indexing complete!"
        '';

      in {
        packages = {
          inherit kant-pastebin index-docs;

          nora = nora.packages.${system}.nora-registry;
          kellnr = kellnr.packages.${system}.default;
          pipelight = pipelight.packages.${system}.default;
          default = kant-pastebin;
        };

        apps = {
          kant-pastebin = {
            type = "app";
            program = "${kant-pastebin}/bin/kant-pastebin";
          };
          multi-reindex = {
            type = "app";
            program = "${kant-pastebin}/bin/multi-reindex";
          };
          default = self.apps.${system}.kant-pastebin;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            cargo rustc rust-analyzer rustfmt clippy pkg-config openssl.dev
          ] ++ [
            self.packages.${system}.pipelight
            self.packages.${system}.kellnr
            system-manager.packages.${system}.default
          ];
          shellHook = ''
            export PKG_CONFIG_PATH="${pkgs.openssl.dev}/lib/pkgconfig:$PKG_CONFIG_PATH"
            echo "Kant Pastebin dev shell — OpenSSL, pkg-config ready"
          '';
        };
      }
    )
    // {
      # System-manager configuration for declarative deployment
      # Usage: nix run github:numtide/system-manager -- switch --flake .#kant-pastebin
      systemConfigs.kant-pastebin = system-manager.lib.makeSystemConfig {
        modules = [
          ./system-manager-config.nix
          { nixpkgs.hostPlatform = "x86_64-linux"; }
        ];
        specialArgs = { inherit self zos-circuit-tile org-tile; };
      };

      # Usage: nix run github:numtide/system-manager -- switch --flake .#kellnr
      systemConfigs.kellnr = system-manager.lib.makeSystemConfig {
        modules = [
          ./modules/postgresql.nix
          ./kellnr-system-manager-config.nix
          { nixpkgs.hostPlatform = "x86_64-linux"; }
        ];
        specialArgs = { inherit self; };
      };

      # Usage: nix run github:numtide/system-manager -- switch --flake .#nora
      systemConfigs.nora = system-manager.lib.makeSystemConfig {
        modules = [
          "${nora}/nora-system-manager.nix"
          { nixpkgs.hostPlatform = "x86_64-linux"; }
        ];
        # Pass the nora flake as `self` so the module can find its packages
        specialArgs = { self = nora; };
      };
    };
}
