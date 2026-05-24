{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "tower-service
tower_service";
  version = "0.3.3
0.3.22
0.2
1.6.2
0.3";
  src = ././vendor/tower-service-0.3.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "tower-service
tower_service";
  #   license = lib.licenses.mit;
  # };
}
