{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "try-lock";
  version = "0.2.5";
  src = ././vendor/try-lock-0.2.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "try-lock";
  #   license = lib.licenses.mit;
  # };
}
