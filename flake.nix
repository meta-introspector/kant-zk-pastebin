{
  description = "Kant Pastebin - UUCP + zkTLS";

  inputs = {
    nixpkgs.url = "git+file:///mnt/data1/git/github.com/NixOS/nixpkgs.git?ref=omaster";
    flake-utils.url = "git+file:///mnt/data1/git/github.com/numtide/flake-utils.git?ref=omain";
    crane.url = "path:/mnt/data1/time-2026/05-may/19/crane";
    nora-cargo = {
      url = "path:/mnt/data1/nora/storage/cargo";
      flake = false;
    };
    system-manager.url = "git+file:///mnt/data1/git/github.com/numtide/system-manager.git?ref=omain";
  };

  outputs = { self, nixpkgs, flake-utils, system-manager, crane, nora-cargo }:
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        craneLibOrig = crane.mkLib pkgs;
        craneLib = craneLibOrig.appendCrateRegistries [
          (craneLibOrig.registryFromDownloadUrl {
            indexUrl = "https://solana.solfunmeme.com/nora/cargo/index/";
            dl = "https://solana.solfunmeme.com/nora/cargo/api/v1/crates/{crate}/{version}/download";
            fetchurlExtraArgs = { };
            registryPrefix = "sparse+";
          })
        ];
        src = self;

        gitRev = self.shortRev or "dirty";

        commonArgs = {
          inherit src;
          cargoVendorDir = null;
          strictDeps = true;
          doCheck = false;

          nativeBuildInputs = with pkgs; [ pkg-config ];
          buildInputs = with pkgs; [ openssl ];

          doInstallCargoArtifacts = false;
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/bin"
            BIN=$(find target -name "kant-pastebin" -type f -executable | head -1)
            if [ -z "$BIN" ]; then
              BIN=$(find target -name "kant-pastebin*" -type f -executable | head -1)
            fi
            cp "$BIN" "$out/bin/kant-pastebin"
            CLI=$(find target -name "svg2tile-cli" -type f -executable | head -1)
            if [ -n "$CLI" ]; then
              cp "$CLI" "$out/bin/svg2tile-cli"
            fi
            runHook postInstall
          '';
        };

        cargoArtifacts = craneLib.buildDepsOnly (commonArgs // {
          cargoExtraArgs = "--offline";
        });

        kant-pastebin = craneLib.cargoBuild (commonArgs // {
          inherit cargoArtifacts;
          pnameSuffix = "";

          meta = with pkgs.lib; {
            description = "Kant Pastebin — UUCP + zkTLS with IPFS";
            license = licenses.mit;
            platforms = platforms.linux;
          };
        });
      in {
        packages = {
          inherit kant-pastebin;
          default = kant-pastebin;
        };

        apps.default = {
          type = "app";
          program = "${kant-pastebin}/bin/kant-pastebin";
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            rustc cargo rustfmt clippy
            openssl.dev pkg-config
          ];
        };
      }
    )) // {
      systemConfigs.kant-pastebin-only = system-manager.lib.makeSystemConfig {
        modules = [
          ./pastebin-system.nix
          { nixpkgs.hostPlatform = "x86_64-linux"; }
        ];
        specialArgs = { pastebin-src = self; };
      };
    };
}