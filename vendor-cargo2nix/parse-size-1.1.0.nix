{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "parse-size
parse_size";
  version = "1.1.0
4.5";
  src = ././vendor/parse-size-1.1.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "parse-size
parse_size";
  #   license = lib.licenses.mit;
  # };
}
