{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "match-lookup
match_lookup";
  version = "0.1.2
1.0
1.0
2.0";
  src = ././vendor/match-lookup-0.1.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "match-lookup
match_lookup";
  #   license = lib.licenses.mit;
  # };
}
