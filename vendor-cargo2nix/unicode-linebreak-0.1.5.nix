{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "unicode-linebreak";
  version = "0.1.5";
  src = ././vendor/unicode-linebreak-0.1.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "unicode-linebreak";
  #   license = lib.licenses.mit;
  # };
}
