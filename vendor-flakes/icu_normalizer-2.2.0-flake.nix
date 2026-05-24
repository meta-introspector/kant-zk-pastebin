{ pkgs ? import <nixpkgs> {} }:

let
  cargo2nix = pkgs.callPackage (pkgs.fetchFromGitHub {
    owner = "cargo2nix";
    repo = "cargo2nix";
    rev = "master";
    sha256 = "0z1j2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p7q8r9s0t1u2v3w4x5y6z7a8b9c0d1e2f3";
  }) {};
in
{
  description = "Vendored crate: icu_normalizer
icu_normalizer
tests
bench
canonical_composition
canonical_decomposition
composing_normalizer_nfc
composing_normalizer_nfkc
decomposing_normalizer_nfd
decomposing_normalizer_nfkd
utf16_throughput (2.2.0
0.2.0
0.6.0
~2.2.0
~2.2.0
~2.2.0
2.2.0
1.0.220
1.10.0
1.0.2
1.0.2
1.0.0
0.11.6
0.3.0
0.7.2
2.0.0
1.0.0
1.0.0
0.5.0)";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    cargo2nix.url = "github:cargo2nix/cargo2nix";
  };
  
  outputs = { self, nixpkgs, cargo2nix }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      cargo2nixPkgs = cargo2nix.packages.${system};
      
    in {
      packages.${system}.icu_normalizer-2.2.0 = cargo2nixPkgs.mkRustCrate {
        name = "icu_normalizer
icu_normalizer
tests
bench
canonical_composition
canonical_decomposition
composing_normalizer_nfc
composing_normalizer_nfkc
decomposing_normalizer_nfd
decomposing_normalizer_nfkd
utf16_throughput";
        version = "2.2.0
0.2.0
0.6.0
~2.2.0
~2.2.0
~2.2.0
2.2.0
1.0.220
1.10.0
1.0.2
1.0.2
1.0.0
0.11.6
0.3.0
0.7.2
2.0.0
1.0.0
1.0.0
0.5.0";
        src = ././vendor/icu_normalizer-2.2.0;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.icu_normalizer-2.2.0;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
