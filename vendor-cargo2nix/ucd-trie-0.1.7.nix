{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "ucd-trie
ucd_trie
bench";
  version = "0.1.7
1";
  src = ././vendor/ucd-trie-0.1.7;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "ucd-trie
ucd_trie
bench";
  #   license = lib.licenses.mit;
  # };
}
