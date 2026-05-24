{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "ipld-core
ipld_core
macros
serde_deserialize
serde_deserializer
serde_serialize
serde_serializer";
  version = "0.4.3
0.11.1
1.0
1.0.195
0.11.5
1.0.197
0.6.0
0.2.0
1.0.79
1.0.132";
  src = ././vendor/ipld-core-0.4.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "ipld-core
ipld_core
macros
serde_deserialize
serde_deserializer
serde_serialize
serde_serializer";
  #   license = lib.licenses.mit;
  # };
}
