{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
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
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "plotters
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
  #   license = lib.licenses.mit;
  # };
}
