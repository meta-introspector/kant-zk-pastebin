{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "compact_str
compact_str";
  version = "0.9.0
1
1
1
0.2.3
1
2
1
0.15
1
1
0.8
1
1
1
1
0.8
1
1
1
1
1
1
1
0.8.8
1
1
3
0.3";
  src = ././vendor/compact_str-0.9.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "compact_str
compact_str";
  #   license = lib.licenses.mit;
  # };
}
