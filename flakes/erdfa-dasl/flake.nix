{
  description = "erdfa-dasl — microflake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    erdfa-dasl = {
      url = "git+file:///home/mdupont/git/github.com/meta-introspector/erdfa-dasl.git";
      flake = false;
    };
    zkperf = {
      url = "git+file:///home/mdupont/git/github.com/meta-introspector/zkperf.git";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, erdfa-dasl, zkperf }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      # Combine erdfa-dasl source with its path deps (zkperf-macros, zkperf-witness)
      # at the expected relative paths
      crateSrc = pkgs.runCommand "erdfa-dasl-src" { } ''
        mkdir -p $out/plugins/erdfa-dasl $out/zkperf
        cp -r ${erdfa-dasl}/* $out/plugins/erdfa-dasl/
        cp -r ${zkperf}/zkperf-macros $out/zkperf/
        cp -r ${zkperf}/zkperf-witness $out/zkperf/
        chmod -R +w $out/
        cp ${./Cargo.lock} $out/Cargo.lock
        cat > $out/Cargo.toml << 'TOML'
[workspace]
members = ["plugins/erdfa-dasl", "zkperf/zkperf-macros", "zkperf/zkperf-witness"]
resolver = "2"
TOML
      '';
    in {
      packages.${system}.default = pkgs.rustPlatform.buildRustPackage rec {
        pname = "erdfa-dasl";
        version = "0.1.0";
        src = crateSrc;
        cargoLock.lockFile = crateSrc + "/Cargo.lock";
        doCheck = false;
        installPhase = ''
          mkdir -p $out/lib
          find target/release -maxdepth 1 -name "*.so" -exec cp -t $out/lib {} \;
          find target/release -maxdepth 1 -name "*.rlib" -exec cp -t $out/lib {} \;
        '';
      };
    };
}
