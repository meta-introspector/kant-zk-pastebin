{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "num-iter";
  version = "0.1.45
0.1.46
0.2.11
1";
  src = ././vendor/num-iter-0.1.45;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "num-iter";
  #   license = lib.licenses.mit;
  # };
}
