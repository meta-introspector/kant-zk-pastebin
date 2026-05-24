{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "percent-encoding
percent_encoding";
  version = "2.3.2";
  src = ././vendor/percent-encoding-2.3.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "percent-encoding
percent_encoding";
  #   license = lib.licenses.mit;
  # };
}
