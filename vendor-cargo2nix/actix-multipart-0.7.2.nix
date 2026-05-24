{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "actix-multipart";
  version = "0.7.2
=0.7.0
3
4
0.99.5
0.3.17
0.3.17
1.3
0.1
0.4
2.5
0.3
0.8
1
1
1
3.4
1.24.2
3
0.10
2.2
0.1
4
1
3
0.11
0.3
0.3.17
3
1.24.2
0.1";
  src = ././vendor/actix-multipart-0.7.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "actix-multipart";
  #   license = lib.licenses.mit;
  # };
}
