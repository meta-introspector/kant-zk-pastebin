{ pkgs, noraUrl ? "http://127.0.0.1:4000", ... }:

let
  noraIndex = "${noraUrl}/cargo/index";

  cargoConfigToml = ''
    [source.crates-io]
    replace-with = "nora"

    [source.nora]
    registry = "sparse+${noraIndex}/"
  '';

  preBuildInject = ''
    export CARGO_HOME="$PWD/.cargo-home"
    mkdir -p "$CARGO_HOME"
    mkdir -p .cargo
    cat > .cargo/config.toml << 'NORA_EOF'
${cargoConfigToml}
NORA_EOF
  '';

  inject = attrs: attrs // {
    preBuild = (attrs.preBuild or "") + preBuildInject;
    CARGO_HOME = ".cargo-home";
    NORA_URL = noraUrl;
  };
in {
  inherit cargoConfigToml noraIndex noraUrl;

  buildRustPackage = args: pkgs.rustPlatform.buildRustPackage (inject args);
  cargoConfigFile = pkgs.writeText "nora-cargo-config.toml" cargoConfigToml;
}
