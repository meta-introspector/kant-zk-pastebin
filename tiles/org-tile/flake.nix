{
  description = "org-tile: org-mode document renderer as standalone cdylib";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.rustPlatform.buildRustPackage rec {
          pname = "org-tile";
          version = "0.1.0";

          src = pkgs.lib.cleanSource ./.;

          cargoLock = {
            lockFile = ./Cargo.lock;
          };

          installPhase = ''
            mkdir -p $out/lib
            find target -name "*.so" -exec cp {} $out/lib/ \;
            ls -la $out/lib/
          '';

          buildInputs = with pkgs; [
          ];

          nativeBuildInputs = with pkgs; [
          ];

          doCheck = false;
        };
      }
    );
}
