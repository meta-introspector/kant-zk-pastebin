{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "plotters-backend
plotters_backend";
  version = "0.3.7";
  src = ././vendor/plotters-backend-0.3.7;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "plotters-backend
plotters_backend";
  #   license = lib.licenses.mit;
  # };
}
