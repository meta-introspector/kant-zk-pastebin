{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "winapi";
  version = "0.3.9
0.4
0.4";
  src = ././vendor/winapi-0.3.9;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "winapi";
  #   license = lib.licenses.mit;
  # };
}
