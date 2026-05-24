{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "local-channel";
  version = "0.1.5
0.3.17
0.3.17
0.1";
  src = ././vendor/local-channel-0.1.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "local-channel";
  #   license = lib.licenses.mit;
  # };
}
