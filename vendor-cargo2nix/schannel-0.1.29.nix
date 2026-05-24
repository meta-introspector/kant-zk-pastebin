{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "schannel
schannel";
  version = "0.1.29
0.61
0.61";
  src = ././vendor/schannel-0.1.29;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "schannel
schannel";
  #   license = lib.licenses.mit;
  # };
}
