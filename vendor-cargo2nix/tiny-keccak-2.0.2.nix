{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "tiny-keccak
sha3
keccak
cshake
tuple_hash
kangaroo
sha3
shake
kmac
parallel_hash
keccak
kangaroo";
  version = "2.0.2
0.2.2";
  src = ././vendor/tiny-keccak-2.0.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "tiny-keccak
sha3
keccak
cshake
tuple_hash
kangaroo
sha3
shake
kmac
parallel_hash
keccak
kangaroo";
  #   license = lib.licenses.mit;
  # };
}
