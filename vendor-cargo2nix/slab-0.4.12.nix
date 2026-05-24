{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "slab
slab
serde
slab";
  version = "0.4.12
1.0.95
1
1";
  src = ././vendor/slab-0.4.12;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "slab
slab
serde
slab";
  #   license = lib.licenses.mit;
  # };
}
