{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "webpki-roots
webpki_roots
codegen
verify";
  version = "1.0.7
1.8
1.15.2
0.4.3
2.3
0.14.3
0.23
1
0.103
0.18
0.6";
  src = ././vendor/webpki-roots-1.0.7;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "webpki-roots
webpki_roots
codegen
verify";
  #   license = lib.licenses.mit;
  # };
}
