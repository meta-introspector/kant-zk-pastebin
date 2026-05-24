{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "hyper-tls";
  version = "0.5.0
1
0.14.2
0.2.1
1
0.3
0.14.2
1.0.0";
  src = ././vendor/hyper-tls-0.5.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "hyper-tls";
  #   license = lib.licenses.mit;
  # };
}
