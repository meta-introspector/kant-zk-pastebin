{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "const-str";
  version = "0.4.3
=0.4.2
0.4.0
0.2.8
1.5.6";
  src = ././vendor/const-str-0.4.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "const-str";
  #   license = lib.licenses.mit;
  # };
}
