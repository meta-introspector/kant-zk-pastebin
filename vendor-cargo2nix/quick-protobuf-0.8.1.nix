{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "quick-protobuf";
  version = "0.8.1
1.3.4
1.4.0
1.0.71";
  src = ././vendor/quick-protobuf-0.8.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "quick-protobuf";
  #   license = lib.licenses.mit;
  # };
}
