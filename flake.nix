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
        lib = nixpkgs.lib;
        pkgs = import nixpkgs {
          inherit system;
        };

        craneLibOrig = crane.mkLib pkgs;
        craneLib = craneLibOrig.appendCrateRegistries [
          (craneLibOrig.registryFromDownloadUrl {
            indexUrl = "https://solana.solfunmeme.com/nora/cargo/index/";
            registryPrefix = "sparse+";
            dl = "file://${nora-cargo}/{crate}/{version}/{crate}-{version}.crate";
          })
        ];
        src = self;

        gitRev = self.shortRev or "dirty";

        noraCargoPackage = p: pkgs.runCommand "cargo-package-${p.name}-${p.version}" {
          nativeBuildInputs = [ pkgs.gnutar pkgs.gzip ];
          crate = nora-cargo + "/${p.name}/${p.version}/${p.name}-${p.version}.crate";
        } ''
          mkdir -p "$out"
          tar -xzf "$crate" -C "$out" --strip-components=1 --no-same-owner
          echo "{\"files\":{},\"package\":\"${p.checksum}\"}" > "$out/.cargo-checksum.json"
        '';

        # Use buildDepsOnly with overrideCargoVendorCrate to handle nora packages.
        # vendorCargoDeps + overrideVendorCargoPackage does not work for sparse+
        # registries in the Nix sandbox (see commit e7629548).
        # appendCrateRegistries tells crane how to download from the nora registry,
        # while overrideCargoVendorCrate intercepts and uses local .crate files.
        cargoArtifacts = craneLib.buildDepsOnly {
          name = "kant-pastebin-deps";
          src = src;
          overrideCargoVendorCrate = p: drv:
            if lib.strings.hasPrefix "sparse+https://solana.solfunmeme.com/nora/cargo/index/" (p.source or "") then
              noraCargoPackage p
            else
              drv;
        };

        commonArgs = {
          inherit src;
          inherit cargoArtifacts;
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

        kant-pastebin = craneLib.cargoBuild (commonArgs // {
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
