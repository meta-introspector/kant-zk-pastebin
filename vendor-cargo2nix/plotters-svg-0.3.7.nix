{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "plotters-svg
plotters_svg";
  version = "0.3.7
0.24.2
0.3.6";
  src = ././vendor/plotters-svg-0.3.7;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "plotters-svg
plotters_svg";
  #   license = lib.licenses.mit;
  # };
}
