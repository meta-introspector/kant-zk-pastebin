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

        noraCargoStorage = builtins.path {
          path = /mnt/data1/nora/storage/cargo;
          name = "nora-cargo-storage";
        };

        noraCargoVendor = pkgs.runCommand "nora-cargo-vendor" {
          src = noraCargoStorage;
        } ''
          mkdir -p "$out"
          cp -R "$src"/. "$out"/
          chmod -R u+w "$out"
          cat > "$out/config.toml" <<'NORA_VENDOR_EOF'
[source.crates-io]
replace-with = "nora"

[source.nora]
directory = "$out"
NORA_VENDOR_EOF
        '';

        kant-pastebin = pkgs.rustPlatform.buildRustPackage {

          pname = "kant-pastebin";
          version = "0.1.0";

          src = pastebin-src;
          cargoLock.lockFile = "${pastebin-src}/Cargo.lock";
          cargoVendorDir = noraCargoVendor;

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
