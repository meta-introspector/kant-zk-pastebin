{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "no_std_io2
no_std_io2
tests";
  version = "0.8.1
2";
  src = ././vendor/no_std_io2-0.8.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "no_std_io2
no_std_io2
tests";
  #   license = lib.licenses.mit;
  # };
}
