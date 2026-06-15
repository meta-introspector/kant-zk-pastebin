{
  description = "Kant Pastebin - UUCP + zkTLS";

  inputs = {
    nixpkgs.url = "git+file:///mnt/data1/git/github.com/NixOS/nixpkgs.git?ref=master";
    flake-utils.url = "git+file:///mnt/data1/git/github.com/numtide/flake-utils.git?ref=main";

    common-inputs = {
      url = "git+file:///home/mdupont/git/solana.solfunmeme.com/nix-common?ref=main";
    };

    pastebin-src = {
      url = "git+file:///mnt/data1/git/github.com/meta-introspector/kant-zk-pastebin?ref=main-clean";
      flake = false;
    };

    system-manager = {
      url = "git+file:///mnt/data1/git/github.com/numtide/system-manager.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, common-inputs, pastebin-src, system-manager }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        noraCfg = import ./lib/nora-cargo-config.nix {
          inherit pkgs;
          noraRegistryUrl = "https://solana.solfunmeme.com/nora";
        };

        cargoVendorDir = pkgs.runCommand "kant-pastebin-cargo-vendor" {
          nativeBuildInputs = [ pkgs.cargo ];
          src = pastebin-src;
          CARGO_HOME = ".cargo-home";
        } ''
          export CARGO_HOME="$PWD/.cargo-home"
          mkdir -p "$CARGO_HOME"
          mkdir -p .cargo
          cat > .cargo/config.toml << 'NORA_VENDOR_EOF'
${noraCfg.cargoConfigToml}
NORA_VENDOR_EOF
          cargo vendor --locked --manifest-path "$src/Cargo.toml" "$out"
        '';

        kant-pastebin = noraCfg.buildRustPackage {
          pname = "kant-pastebin";
          version = "0.1.0";

          src = pastebin-src;
          cargoLock.lockFile = "${pastebin-src}/Cargo.lock";
          cargoVendorDir = cargoVendorDir;

          nativeBuildInputs = with pkgs; [ pkg-config ];
          buildInputs = with pkgs; [ openssl ];

          doCheck = false;

          meta = with pkgs.lib; {
            description = "Kant Pastebin — UUCP + zkTLS with IPFS";
            license = licenses.mit;
            platforms = platforms.linux;
          };
        };
      in {
        packages = {
          inherit kant-pastebin;
          default = kant-pastebin;
        };

        apps.default = {
          type = "app";
          program = "${kant-pastebin}/bin/kant-pastebin";
        };
      }
    )
    // {
      systemConfigs.kant-pastebin-only = system-manager.lib.makeSystemConfig {
        modules = [
          ./pastebin-system-manager-only.nix
          { nixpkgs.hostPlatform = "x86_64-linux"; }
        ];
        specialArgs = { inherit self; };
      };
    };
}
