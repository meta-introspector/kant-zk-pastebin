{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "hermit-abi";
  version = "0.1.19
0.1
1.0.0
0.2.51";
  src = ././vendor/hermit-abi-0.1.19;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "hermit-abi";
  #   license = lib.licenses.mit;
  # };
}
