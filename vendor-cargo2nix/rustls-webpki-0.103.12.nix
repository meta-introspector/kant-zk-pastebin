{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "rustls-webpki
webpki";
  version = "0.103.12
1.14
1.12
0.17
0.9
0.22
0.1.5
0.6
1.17.2
0.14.2
1.0
1.0
0.18.1";
  src = ././vendor/rustls-webpki-0.103.12;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "rustls-webpki
webpki";
  #   license = lib.licenses.mit;
  # };
}
