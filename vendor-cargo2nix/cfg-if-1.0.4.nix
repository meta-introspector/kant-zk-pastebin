{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "cfg-if
cfg_if
xcrate";
  version = "1.0.4
1.0.0";
  src = ././vendor/cfg-if-1.0.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "cfg-if
cfg_if
xcrate";
  #   license = lib.licenses.mit;
  # };
}
