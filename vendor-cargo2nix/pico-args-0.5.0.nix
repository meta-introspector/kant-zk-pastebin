{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "pico-args";
  version = "0.5.0";
  src = ././vendor/pico-args-0.5.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "pico-args";
  #   license = lib.licenses.mit;
  # };
}
