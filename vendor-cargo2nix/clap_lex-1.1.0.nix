{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "clap_lex
clap_lex";
  version = "1.1.0
1.0.16";
  src = ././vendor/clap_lex-1.1.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "clap_lex
clap_lex";
  #   license = lib.licenses.mit;
  # };
}
