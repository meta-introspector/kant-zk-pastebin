{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "serde_urlencoded";
  version = "0.7.1
1
1
1
1.0.69
1";
  src = ././vendor/serde_urlencoded-0.7.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "serde_urlencoded";
  #   license = lib.licenses.mit;
  # };
}
