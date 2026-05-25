{
  description = "zkperf-witness — microflake";

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
      crateSrc = pkgs.runCommand "zkperf-witness-src" { } ''
        mkdir -p $out/zkperf
        cp -r ${zkperf}/zkperf-witness $out/zkperf/
        cp -r ${zkperf}/zkperf-macros $out/zkperf/
        chmod -R +w $out/
        cp ${./Cargo.lock} $out/Cargo.lock
        cat > $out/Cargo.toml << 'TOML'
[workspace]
members = ["zkperf/zkperf-witness", "zkperf/zkperf-macros"]
resolver = "2"
TOML
      '';
    in {
      packages.${system}.default = pkgs.rustPlatform.buildRustPackage {
        pname = "zkperf-witness";
        version = "0.1.0";
        src = crateSrc;
        cargoLock.lockFile = crateSrc + "/Cargo.lock";
        doCheck = false;
      };
    };
}
