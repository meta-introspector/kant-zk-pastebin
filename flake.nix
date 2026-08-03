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
        pkgs = import nixpkgs { inherit system; };

        craneLibOrig = crane.mkLib pkgs;
        craneLib = craneLibOrig.appendCrateRegistries [
          (craneLibOrig.registryFromDownloadUrl {
            indexUrl = "https://solana.solfunmeme.com/nora/cargo/index/";
            dl = "file://${nora-cargo}/{crate}/{version}/{crate}-{version}.crate";
            registryPrefix = "sparse+";
          })
        ];
        src = self;

        noraCargoPackage = p: pkgs.runCommand "cargo-package-${p.name}-${p.version}" {
          nativeBuildInputs = [ pkgs.gnutar pkgs.gzip ];
          crate = "${nora-cargo}/${p.name}/${p.version}/${p.name}-${p.version}.crate";
        } ''
          mkdir -p "$out"
          tar -xzf "$crate" -C "$out" --strip-components=1 --no-same-owner
          echo "{\"files\":{},\"package\":\"${p.checksum}\"}" > "$out/.cargo-checksum.json"
        '';

        rawVendorDeps = craneLib.vendorCargoDeps {
          inherit src;
          overrideVendorCargoPackage = p: drv:
            if lib.strings.hasPrefix "sparse+https://solana.solfunmeme.com/nora/cargo/index/" (p.source or "")
            then noraCargoPackage p
            else drv;
        };

        # Merge all vendor subdirs into one so cargo finds ALL packages
        # (crates-io + nora) in a single directory
        cargoVendorDir = pkgs.runCommand "unified-vendor-deps" {} ''
          mkdir -p "$out/registry"
          for d in ${rawVendorDeps}/*/; do
            cp -rn "$d"* "$out/registry/" 2>/dev/null || true
          done
          chmod -R u+w "$out/registry"
          cat > "$out/config.toml" << EOF
[source.unified]
directory = "$out/registry"
[source.crates-io]
registry = "https://github.com/rust-lang/crates.io-index"
replace-with = "unified"
[source.nora]
registry = "sparse+https://solana.solfunmeme.com/nora/cargo/index/"
replace-with = "unified"
EOF
        '';

        commonArgs = {
          inherit src cargoVendorDir;
          strictDeps = true;
          doCheck = false;
          cargoExtraArgs = "--offline";
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
        packages = { inherit kant-pastebin; default = kant-pastebin; };
        apps.default = { type = "app"; program = "${kant-pastebin}/bin/kant-pastebin"; };
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [ rustc cargo rustfmt clippy openssl.dev pkg-config ];
        };
      }
    )) // {
      systemConfigs.kant-pastebin-only = system-manager.lib.makeSystemConfig {
        modules = [ ./pastebin-system.nix { nixpkgs.hostPlatform = "x86_64-linux"; } ];
        specialArgs = { pastebin-src = self; };
      };
    };
}
