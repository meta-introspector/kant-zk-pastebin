{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "escape8259";
  version = "0.5.3
1.0";
  src = ././vendor/escape8259-0.5.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "escape8259";
  #   license = lib.licenses.mit;
  # };
}
