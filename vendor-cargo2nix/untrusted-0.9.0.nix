{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "untrusted
untrusted";
  version = "0.9.0";
  src = ././vendor/untrusted-0.9.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "untrusted
untrusted";
  #   license = lib.licenses.mit;
  # };
}
