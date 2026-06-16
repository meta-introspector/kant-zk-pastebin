{
  description = "Kant Pastebin - UUCP + zkTLS";

  inputs = {
    nixpkgs.url = "git+file:///mnt/data1/git/github.com/NixOS/nixpkgs.git?ref=master";
    flake-utils.url = "git+file:///mnt/data1/git/github.com/numtide/flake-utils.git?ref=main";

    common-inputs = {
      url = "git+file:///home/mdupont/git/solana.solfunmeme.com/nix-common?ref=main";
    };

    crane = {
      url = "path:/mnt/data1/time-2026/05-may/19/crane";
    };

    pastebin-src = {
      url = "git+file:///mnt/data1/git/github.com/meta-introspector/kant-zk-pastebin?ref=main-clean";
      flake = false;
    };

    nora-cargo = {
      url = "path:/mnt/data1/nora/storage/cargo";
      flake = false;
    };

    system-manager = {
      url = "git+file:///mnt/data1/git/github.com/numtide/system-manager.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, common-inputs, crane, pastebin-src, nora-cargo, system-manager }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        craneLib = crane.mkLib pkgs;
        src = pastebin-src;

        noraCargoPackage = p: pkgs.runCommand "cargo-package-${p.name}-${p.version}" {
          nativeBuildInputs = [ pkgs.gnutar pkgs.gzip ];
          crate = nora-cargo + "/${p.name}/${p.version}/${p.name}-${p.version}.crate";
        } ''
          mkdir -p "$out"
          tar -xzf "$crate" -C "$out" --strip-components=1 --no-same-owner
          echo "{\"files\":{},\"package\":\"${p.checksum}\"}" > "$out/.cargo-checksum.json"
        '';

        cargoVendorDir = craneLib.vendorCargoDeps {
          src = pastebin-src;
          overrideVendorCargoPackage = p: drv:
            if p.name == "erdfa-publish" || p.name == "rust-unixfs" then
              noraCargoPackage p
            else
              drv;
        };

        commonArgs = {
          inherit src;
          inherit cargoVendorDir;
          strictDeps = true;
          doCheck = false;

          nativeBuildInputs = with pkgs; [ pkg-config ];
          buildInputs = with pkgs; [ openssl ];

          doInstallCargoArtifacts = false;
        };

        cargoArtifacts = craneLib.buildDepsOnly commonArgs;

        kant-pastebin = craneLib.cargoBuild (commonArgs // {
          inherit cargoArtifacts;
          pnameSuffix = "";

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
