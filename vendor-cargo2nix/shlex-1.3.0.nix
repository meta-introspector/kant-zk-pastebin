{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "shlex";
  version = "1.3.0";
  src = ././vendor/shlex-1.3.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "shlex";
  #   license = lib.licenses.mit;
  # };
}
