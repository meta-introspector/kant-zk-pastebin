{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "deunicode
deunicode";
  version = "1.6.2";
  src = ././vendor/deunicode-1.6.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "deunicode
deunicode";
  #   license = lib.licenses.mit;
  # };
}
