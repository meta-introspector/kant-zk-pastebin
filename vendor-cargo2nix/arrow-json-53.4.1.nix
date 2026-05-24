{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "arrow-json
arrow_json
serde";
  version = "53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
>= 0.4.34, < 0.4.40
2.1
2.0
1.0
0.4
1.0
1.0
1.4
0.5
1
0.3
0.8
1.0
3.3
1.27";
  src = ././vendor/arrow-json-53.4.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "arrow-json
arrow_json
serde";
  #   license = lib.licenses.mit;
  # };
}
