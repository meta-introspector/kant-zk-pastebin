{
  description = "zos-circuit-optimizer — microflake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zos-circuit-optimizer = {
      url = "git+file:///mnt/data1/git/solana.solfunmeme.com/zos-circuit-optimizer.git";
      flake = false;
    };
    erdfa-dasl = {
      url = "git+file:///home/mdupont/git/github.com/meta-introspector/erdfa-dasl.git";
      flake = false;
    };
    zkperf = {
      url = "git+file:///home/mdupont/git/github.com/meta-introspector/zkperf.git";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      zco = inputs.zos-circuit-optimizer;
      edl = inputs.erdfa-dasl;
      zk  = inputs.zkperf;

      crateSrc = pkgs.runCommand "zos-circuit-optimizer-src" { } ''
        mkdir -p $out/plugins/zos-circuit-optimizer $out/plugins/erdfa-dasl $out/zkperf
        cp -r ${zco}/* $out/plugins/zos-circuit-optimizer/
        cp -r ${edl}/* $out/plugins/erdfa-dasl/
        cp -r ${zk}/zkperf-macros $out/zkperf/
        cp -r ${zk}/zkperf-witness $out/zkperf/
        chmod -R +w $out/
        cp ${./Cargo.lock} $out/Cargo.lock
        cat > $out/Cargo.toml << 'TOML'
[workspace]
members = ["plugins/zos-circuit-optimizer", "plugins/erdfa-dasl", "zkperf/zkperf-macros", "zkperf/zkperf-witness"]
resolver = "2"
TOML
      '';
    in {
      packages.${system}.default = pkgs.rustPlatform.buildRustPackage rec {
        pname = "zos-circuit-optimizer";
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
