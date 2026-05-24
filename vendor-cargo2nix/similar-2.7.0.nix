{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "similar
similar
close-matches
large
nonstring
original-slices
patience
serde
terminal
terminal-inline
udiff";
  version = "2.7.0
1.5.0
1.0.130
1.7.1
1.1
0.15.0
1.10.0
1.0.68";
  src = ././vendor/similar-2.7.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "similar
similar
close-matches
large
nonstring
original-slices
patience
serde
terminal
terminal-inline
udiff";
  #   license = lib.licenses.mit;
  # };
}
