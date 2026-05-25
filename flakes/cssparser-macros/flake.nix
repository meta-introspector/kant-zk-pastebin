{
  description = "cssparser-macros — minimal microflake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-cssparser = {
      url = "git+file:///mnt/data1/git/github.com/servo/rust-cssparser.git?rev=aae89a8330951e441e0010fdd1907be4cb119eb5";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, rust-cssparser }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      # Combine bare mirror source with local Cargo.lock
      crateSrc = pkgs.runCommand "cssparser-macros-src" { } ''
        mkdir -p $out
        cp -r ${rust-cssparser}/macros/* $out/
        chmod -R +w $out/
        cp ${./Cargo.lock} $out/Cargo.lock
      '';
    in {
      packages.${system}.default = pkgs.rustPlatform.buildRustPackage {
        pname = "cssparser-macros";
        version = "0.7.0";
        src = crateSrc;
        cargoLock.lockFile = crateSrc + "/Cargo.lock";
        doCheck = false;
      };
    };
}
