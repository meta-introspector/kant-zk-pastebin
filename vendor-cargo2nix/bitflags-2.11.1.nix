{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "bitflags
bitflags
custom_bits_type
custom_derive
fmt
macro_free
serde
parse";
  version = "2.11.1
1.0
1.12
1.0.228
1.0
1.12.2
1.0
1.0
1.0.103
1.0.19
1.0.18
0.8";
  src = ././vendor/bitflags-2.11.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "bitflags
bitflags
custom_bits_type
custom_derive
fmt
macro_free
serde
parse";
  #   license = lib.licenses.mit;
  # };
}
