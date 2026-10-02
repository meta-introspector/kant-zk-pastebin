{
  description = "Kant Pastebin - UUCP + zkTLS";

  # Every input is something a GitHub runner can fetch. This used to be a set
  # of `file:///mnt/data1/...` URLs, which resolve on exactly one machine and
  # nowhere else — that, plus the `?ref=omain` typo, is why the Nix Build check
  # has been red on this repository since the Oct 1 merges. docs/FLAKE_INPUTS.md
  # has the before/after table, the nora registry, and how to bump an input.
  #
  # Every input is pinned by rev rather than tracking a branch. A branch name
  # here means any upstream commit silently changes what this builds, which is
  # how `?ref=omain` went unnoticed for weeks; and `system-manager` in
  # particular carries a vendored `vendor/` directory that is what makes the
  # build work without crates.io (see ~/gitplan.org), so drifting off the
  # pinned commit is a regression, not an upgrade.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/0954f7ee2f6bb3dc7d4e3d0d8bcb8fd4bde4cfc5";
    flake-utils.url = "github:numtide/flake-utils/11707dc2f618dd54ca8739b309ec4fc024de578b";
    # ipetkov's crane: this depends on unreleased work (cargoTomlConservative,
    # #1062) that is on no release branch.
    crane.url = "github:ipetkov/crane/8833b7dc3c7426ce1110ed6fed31b6f63d74f2dc";
    # 3dd7dbe is the commit that vendored system-manager's 107 crate deps.
    system-manager.url = "github:numtide/system-manager/3dd7dbe51bb2232b7b51295a022c627c99fe14fc";
    browser.url = "path:./browser";
  };

  outputs = { self, nixpkgs, flake-utils, system-manager, crane, browser }:
    let
      # The browser the GUI2Lean4 captures run against, carried in from
      # browser.nix so `--headed` does not depend on the snap package or a
      # Playwright browser download. See that file for why the full Chromium
      # is pinned rather than the headless shell.
      browserPkgs = browser.packages.x86_64-linux;
    in
    (flake-utils.lib.eachDefaultSystem (system:
      let
        lib = nixpkgs.lib;
        pkgs = import nixpkgs { inherit system; };

        craneLibOrig = crane.mkLib pkgs;
        # Crates come from nora, the local registry, over HTTPS. The `dl`
        # template has to be given explicitly: the index advertises
        # `.../api/v1/crates` with cargo's default `{crate}/{version}/...`
        # suffix appended, and that path 404s. The real layout ends in
        # `/download`, and a tarball fetched from it hashes to the `cksum` the
        # index publishes — so cargo can verify it and no fabricated
        # `.cargo-checksum.json` is needed.
        craneLib = craneLibOrig.appendCrateRegistries [
          (craneLibOrig.registryFromDownloadUrl {
            indexUrl = "https://solana.solfunmeme.com/nora/cargo/index/";
            dl = "https://solana.solfunmeme.com/nora/cargo/api/v1/crates/{crate}/{version}/download";
            registryPrefix = "sparse+";
          })
        ];
        src = self;

        # No overrideVendorCargoPackage: it used to untar crates out of a local
        # nora path and write a `.cargo-checksum.json` with an empty file list,
        # which only worked because nothing could check it. Now that nora serves
        # the same tarballs over HTTPS, cargo fetches and verifies them itself.
        rawVendorDeps = craneLib.vendorCargoDeps { inherit src; };

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
          cargoExtraArgs = "--offline";
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
          inherit (browserPkgs) chromium fileshare-capture;
        };
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
