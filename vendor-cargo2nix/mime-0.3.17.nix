{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "mime";
  version = "0.3.17";
  src = ././vendor/mime-0.3.17;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "mime";
  #   license = lib.licenses.mit;
  # };
}
