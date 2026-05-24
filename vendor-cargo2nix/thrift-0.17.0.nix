{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "thrift";
  version = "0.17.0
1.3
3.0.3
0.4
2.0
1.7";
  src = ././vendor/thrift-0.17.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "thrift";
  #   license = lib.licenses.mit;
  # };
}
