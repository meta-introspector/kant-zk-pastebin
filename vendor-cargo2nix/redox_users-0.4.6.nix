{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "redox_users
redox_users";
  version = "0.4.6
0.2
0.1.3
0.8
1.0
1.4";
  src = ././vendor/redox_users-0.4.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "redox_users
redox_users";
  #   license = lib.licenses.mit;
  # };
}
