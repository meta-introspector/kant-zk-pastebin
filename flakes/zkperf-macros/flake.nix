{
  description = "zkperf-macros — minimal microflake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zkperf = {
      url = "git+file:///home/mdupont/git/github.com/meta-introspector/zkperf.git";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, zkperf }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      # Extract just the zkperf-macros subdirectory
      crateSrc = pkgs.runCommand "zkperf-macros-src" { } ''
        mkdir -p $out
        cp -r ${zkperf}/zkperf-macros/* $out/
        chmod -R +w $out/
        cp ${./Cargo.lock} $out/Cargo.lock
      '';
    in {
      packages.${system}.default = pkgs.rustPlatform.buildRustPackage {
        pname = "zkperf-macros";
        version = "0.1.0";
        src = crateSrc;
        cargoLock.lockFile = crateSrc + "/Cargo.lock";
        doCheck = false;
      };
    };
}
