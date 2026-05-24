{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "utf8_iter";
  version = "1.0.4";
  src = ././vendor/utf8_iter-1.0.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "utf8_iter";
  #   license = lib.licenses.mit;
  # };
}
