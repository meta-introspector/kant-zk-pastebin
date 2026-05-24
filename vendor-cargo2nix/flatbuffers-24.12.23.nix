{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "flatbuffers
flatbuffers";
  version = "24.12.23
1.2.1
1.0
0.4.0";
  src = ././vendor/flatbuffers-24.12.23;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "flatbuffers
flatbuffers";
  #   license = lib.licenses.mit;
  # };
}
