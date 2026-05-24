{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "integer-encoding
encode_varint_from_stdin
read_write_file
main";
  version = "3.0.4
0.1
0.3
1.0
~0.1
1.0";
  src = ././vendor/integer-encoding-3.0.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "integer-encoding
encode_varint_from_stdin
read_write_file
main";
  #   license = lib.licenses.mit;
  # };
}
