{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "parse-zoneinfo";
  version = "0.3.1
1.3.1";
  src = ././vendor/parse-zoneinfo-0.3.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "parse-zoneinfo";
  #   license = lib.licenses.mit;
  # };
}
