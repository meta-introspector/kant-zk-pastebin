{
  description = "Custom File Crawler - Analyze files and generate content graphs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    erdfa-canonical = {
      url = "git+file:///home/mdupont/git/solana.solfunmeme.com/erdfa-canonical.git?ref=feat/file-crawler-integration";
      flake = false;
    };
    erdfa-publish = {
      url = "git+file:///mnt/data1/git/solana.solfunmeme.com/erdfa-publish.git?ref=feat/file-crawler-integration";
      flake = false;
    };
    rust-ipfs = {
      url = "github:meta-introspector/rust-ipfs";
      flake = false;
    };
    zkperf = {
      url = "git+file:///mnt/data1/git/github.com/meta-introspector/zkperf.git?ref=feat/regs-ring-shmem-gpu-2026-04-01";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, erdfa-canonical, erdfa-publish, rust-ipfs, zkperf }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Build a patched source tree with all submodules injected
        patchedSrc = pkgs.runCommand "file-crawler-src" {} ''
          cp -r --no-preserve=mode ${self}/. $out
          chmod -R u+w $out
          mkdir -p $out/libs/erdfa-canonical/bindings/rust/vendor
          cp -r --no-preserve=mode ${erdfa-canonical}/. $out/libs/erdfa-canonical
          cp -r --no-preserve=mode ${erdfa-publish}/. $out/libs/erdfa-canonical/bindings/rust
          cp -r --no-preserve=mode ${rust-ipfs}/. $out/libs/erdfa-canonical/bindings/rust/vendor/rust-ipfs
          mkdir -p $out/zkperf
          cp -r --no-preserve=mode ${zkperf}/. $out/zkperf
        '';
      in
      {
        packages.default = pkgs.rustPlatform.buildRustPackage {
          pname = "file-crawler";
          version = "0.1.4";

          src = patchedSrc;

          cargoLock.lockFile = ./Cargo.lock;

          nativeBuildInputs = with pkgs; [ pkg-config ];
          buildInputs = with pkgs; [ openssl ];

          meta = {
            description = "Custom file crawler that analyzes files and generates content graphs";
            platforms = pkgs.lib.platforms.linux;
          };
        };
      }
    );
}
