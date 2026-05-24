{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "ipld-dagpb
ipld_dagpb
codec
compat";
  version = "0.2.2
1.3.0
0.4.0
0.8.1
1.0.25
0.4.3";
  src = ././vendor/ipld-dagpb-0.2.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "ipld-dagpb
ipld_dagpb
codec
compat";
  #   license = lib.licenses.mit;
  # };
}
