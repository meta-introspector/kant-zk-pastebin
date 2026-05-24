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
  description = "Vendored crate: plotters
plotters
3d-plot
3d-plot2
animation
area-chart
blit-bitmap
boxplot
chart
colormaps
console
customized_coord
errorbar
full_palette
histogram
mandelbrot
matshow
nested_coord
normal-dist
normal-dist2
pie
relative_size
sierpinski
slc-temp
snowflake
stock
tick_control
two-scales
benchmark (0.3.7
0.4.32
0.2.14
0.3.6
0.3.6
0.3.6
0.5.1
0.10.0
1.5.1
1.0.139
1.0.140
1.0.82
0.2.89
0.3.66
0.3.39
0.2.12
0.14.2
0.24.3
1.4.0
1.8.0
0.5.1
0.20.0
0.8.3
0.4.0
0.3.0)";
  
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
      packages.${system}.plotters-0.3.7 = cargo2nixPkgs.mkRustCrate {
        name = "plotters
plotters
3d-plot
3d-plot2
animation
area-chart
blit-bitmap
boxplot
chart
colormaps
console
customized_coord
errorbar
full_palette
histogram
mandelbrot
matshow
nested_coord
normal-dist
normal-dist2
pie
relative_size
sierpinski
slc-temp
snowflake
stock
tick_control
two-scales
benchmark";
        version = "0.3.7
0.4.32
0.2.14
0.3.6
0.3.6
0.3.6
0.5.1
0.10.0
1.5.1
1.0.139
1.0.140
1.0.82
0.2.89
0.3.66
0.3.39
0.2.12
0.14.2
0.24.3
1.4.0
1.8.0
0.5.1
0.20.0
0.8.3
0.4.0
0.3.0";
        src = ././vendor/plotters-0.3.7;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.plotters-0.3.7;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
