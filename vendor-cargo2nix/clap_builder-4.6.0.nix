{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "clap_builder
clap_builder";
  version = "4.6.0
1.0.0
1.0.13
0.3.76
1.0.0
0.11.1
0.4.3
2.9.0
0.2.2
0.3.7
1.1.0
1.1.0
0.9.0";
  src = ././vendor/clap_builder-4.6.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "clap_builder
clap_builder";
  #   license = lib.licenses.mit;
  # };
}
