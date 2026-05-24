{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "clap_derive
clap_derive";
  version = "4.6.1
1.0.14
0.5.0
1.0.106
0.13.3
1.0.45
2.0.117";
  src = ././vendor/clap_derive-4.6.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "clap_derive
clap_derive";
  #   license = lib.licenses.mit;
  # };
}
