{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "image
decode
encode
copy_from";
  version = "0.24.9
1.8.0
1.3.2
1.1
0.10.2
0.6.1
1.5.0
0.13
0.3.0
0.2.2
0.17.0
0.2.0
0.17.6
0.4
0.11.0
1.7.0
0.8.25
0.9.0
1.2.0
0.5.0
0.3
0.3.0
0.4
1";
  src = ././vendor/image-0.24.9;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "image
decode
encode
copy_from";
  #   license = lib.licenses.mit;
  # };
}
