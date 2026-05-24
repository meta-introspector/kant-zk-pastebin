{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "lock_api
lock_api";
  version = "0.4.14
0.4.1
1.1.0
1.0.126";
  src = ././vendor/lock_api-0.4.14;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "lock_api
lock_api";
  #   license = lib.licenses.mit;
  # };
}
