# nora-cargo-config.nix — shared Nix library for injecting nora registry into builds
#
# nora.txt analysis (from ~/dasl/index/nora.txt):
#
#   cargo-registry-nora.toml (line215) defines the pattern:
#     [source.crates-io]
#     replace-with = "nora"
#     [source.nora]
#     registry = "http://127.0.0.1:4000/cargo/index"
#
#   Test flakes (line537-542) show injection via preBuild in buildRustPackage.
#   This library provides that injection as a reusable Nix function.
#
# Usage:
#   let noraCfg = import ./lib/nora-cargo-config.nix { inherit pkgs; };
#   in pkgs.rustPlatform.buildRustPackage (noraCfg.inject {
#     pname = "my-crate";
#     version = "1.0.0";
#     src = ./.;
#     cargoLock.lockFile = ./Cargo.lock;
#   })
#
# Or use the wrapped builder directly:
#   noraCfg.buildRustPackage {
#     pname = "my-crate";
#     ...
#   }

{ pkgs, noraUrl ? "http://127.0.0.1:4000", ... }:

let
  noraIndex = "${noraUrl}/cargo/index";

  # The cargo config TOML that replaces crates.io with nora
  cargoConfigToml = ''
    [source.crates-io]
    replace-with = "nora"

    [source.nora]
    registry = "${noraIndex}"
  '';

  # preBuild script that injects .cargo/config.toml into the build dir
  preBuildInject = ''
    mkdir -p .cargo
    cat > .cargo/config.toml << 'NORA_EOF'
    ${cargoConfigToml}
    NORA_EOF
  '';

in {
  # The raw cargo config TOML (for use outside nix builds)
  inherit cargoConfigToml noraIndex noraUrl;

  # Inject nora cargo config into a buildRustPackage attribute set.
  # Takes any buildRustPackage attrs and returns them with preBuild prepended.
  inject = attrs: attrs // {
    preBuild = (attrs.preBuild or "") + preBuildInject;
    # Pass NORA_URL as an env var so builds can detect nora
    NORA_URL = noraUrl;
  };

  # Wrapped rustPlatform.buildRustPackage that automatically injects nora config.
  # Usage: noraCfg.buildRustPackage { pname = ...; ... }
  buildRustPackage = args: pkgs.rustPlatform.buildRustPackage (inject args);

  # Convenience: write the cargo config to a derivation for use in environment.etc
  cargoConfigFile = pkgs.writeText "nora-cargo-config.toml" cargoConfigToml;
}
