{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "zeroize_derive
zeroize_derive";
  version = "1.4.3
1
1
2";
  src = ././vendor/zeroize_derive-1.4.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "zeroize_derive
zeroize_derive";
  #   license = lib.licenses.mit;
  # };
}
