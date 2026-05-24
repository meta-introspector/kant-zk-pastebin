{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "arrow-schema
arrow_schema
ffi";
  version = "53.4.1
2.0.0
1.0
1.3.3
0.5
1.0";
  src = ././vendor/arrow-schema-53.4.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "arrow-schema
arrow_schema
ffi";
  #   license = lib.licenses.mit;
  # };
}
