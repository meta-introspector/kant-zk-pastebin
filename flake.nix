{
  description = "Kant Pastebin - UUCP + zkTLS";

  inputs = {
    nixpkgs.url = "git+file:///mnt/data1/git/github.com/NixOS/nixpkgs.git?ref=omaster";
    flake-utils.url = "git+file:///mnt/data1/git/github.com/numtide/flake-utils.git?ref=omain";
    rust-overlay.url = "git+file:///mnt/data1/git/github.com/oxalica/rust-overlay.git?ref=omaster";
    crane.url = "git+file:///mnt/data1/git/github.com/ipetkov/crane.git?ref=omaster";
    nora-cargo = {
      url = "path:/mnt/data1/nora/storage/cargo";
      flake = false;
    };
    system-manager.url = "git+file:///mnt/data1/git/github.com/numtide/system-manager.git?ref=omain";
  };

  outputs = { self, nixpkgs, flake-utils, system-manager, rust-overlay, crane, nora-cargo }:
    (flake-utils.lib.eachDefaultSystem (system:
      let
        lib = nixpkgs.lib;
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };

        rust = pkgs.rust-bin.stable.latest.default;
        craneLib = (crane.mkLib pkgs).overrideToolchain rust;

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

        cargoVendorDir = craneLib.vendorCargoDeps {
          src = src;
          overrideVendorCargoPackage = p: drv:
            if p.name == "erdfa-publish" || p.name == "rust-unixfs" then
              noraCargoPackage p
            else
              drv;
        };

        commonBuildInputs = with pkgs; [ openssl ];
        commonNativeBuildInputs = with pkgs; [ pkg-config ];

        kant-pastebin = craneLib.buildPackage {
          pname = "kant-pastebin";
          version = "0.1.0";
          src = src;
          cargoVendorDir = cargoVendorDir;
          strictDeps = true;
          doCheck = false;
          buildInputs = commonBuildInputs;
          nativeBuildInputs = commonNativeBuildInputs;
          doInstallCargoArtifacts = false;
          GIT_COMMIT = gitRev;
          BUILD_TIME = builtins.substring 0 19 (builtins.toString self.lastModifiedDate or "unknown");
          BASE_PATH = "/pastebin";

          installPhase = ''
            runHook preInstall
            mkdir -p "$out/bin"
            cp target/release/kant-pastebin "$out/bin/kant-pastebin"
            runHook postInstall
          '';

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

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            rust rust-analyzer
            cargo pkg-config
            openssl.dev
          ];
          shellHook = ''
            export PKG_CONFIG_PATH="${pkgs.openssl.dev}/lib/pkgconfig:$PKG_CONFIG_PATH"
            echo "kant-pastebin dev shell — cargo, rustc, openssl ready"
          '';
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
