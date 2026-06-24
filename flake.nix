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

    nora-cargo = {
      url = "path:/mnt/data1/nora/storage/cargo";
      flake = false;
    };

    system-manager = {
      url = "git+file:///mnt/data1/git/github.com/numtide/system-manager.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, common-inputs, crane, nora-cargo, system-manager }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        craneLib = crane.mkLib pkgs;
        src = self;

        # Git revision embedded into the binary at build time
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
          src = self;
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
          buildInputs = with pkgs; [ openssl.dev ];

          doInstallCargoArtifacts = false;

          # Pass git revision and base path into the build so build.rs can embed them
          GIT_COMMIT = gitRev;
          BASE_PATH = "/pastebin";
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
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            cargo rustc rustfmt clippy
            pkg-config
            stdenv.cc binutils coreutils
          ];
          buildInputs = with pkgs; [
            openssl.dev
            libgit2 curl libssh2 zlib nghttp2
            glibc.dev libc
            snappy lz4 zstd bzip2 liburing
            protobuf protobufc automake autoconf libtool m4
            systemd.dev libusb1 hidapi ncurses util-linux zsh
          ];
          shellHook = ''
            export OPENSSL_DIR="${pkgs.openssl.dev}"
            export PKG_CONFIG_PATH="${pkgs.openssl.dev}/lib/pkgconfig:${pkgs.systemd.dev}/lib/pkgconfig:${pkgs.libusb1.dev}/lib/pkgconfig''${PKG_CONFIG_PATH:+:}$$PKG_CONFIG_PATH"
            export PATH="${pkgs.rustc}/bin:${pkgs.cargo}/bin''${PATH:+:}$$PATH"
            export CC=cc
            export CXX=c++
            export PKG_CONFIG_ALLOW_CROSS=1
            echo "Nix devShell ready: rust + openssl + all system deps"
          '';
        };

        devShells.clang = pkgs.mkShell {
          buildInputs = with pkgs; [ pkg-config openssl.dev clang mold ];
          shellHook = ''
            export OPENSSL_DIR="${pkgs.openssl.dev}"
            export CC=clang CXX=clang++
          '';
        };

        devShells.analysis = pkgs.mkShell {
          buildInputs = with pkgs; [ pkg-config openssl.dev cargo rustc llvmPackages.clang llvmPackages.bintools ];
          shellHook = ''
            export OPENSSL_DIR="${pkgs.openssl.dev}"
          '';
        };

        devShells.leak = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [ cargo rustc pkg-config openssl.dev ];
          buildInputs = with pkgs; [ valgrind ];
          shellHook = ''
            export OPENSSL_DIR="${pkgs.openssl.dev}"
          '';
        };

        devShells.thread = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [ cargo rustc pkg-config openssl.dev ];
          buildInputs = with pkgs; [ heaptrack ];
          shellHook = ''
            export OPENSSL_DIR="${pkgs.openssl.dev}"
          '';
        };

        devShells.sanitizer = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [ cargo rustc pkg-config openssl.dev ];
          shellHook = ''
            export OPENSSL_DIR="${pkgs.openssl.dev}"
            export RUSTFLAGS="-Zsanitizer=address"
          '';
        };

        devShells.tracing = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [ cargo rustc pkg-config openssl.dev ];
          buildInputs = with pkgs; [ linuxPackages.perf ];
          shellHook = ''
            export OPENSSL_DIR="${pkgs.openssl.dev}"
          '';
        };
      in {
        devShells = {
          default = devShells.default;
          clang = devShells.clang;
          analysis = devShells.analysis;
          leak = devShells.leak;
          thread = devShells.thread;
          sanitizer = devShells.sanitizer;
          tracing = devShells.tracing;
        };

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
