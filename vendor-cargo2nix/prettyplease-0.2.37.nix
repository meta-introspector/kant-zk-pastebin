{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "prettyplease
prettyplease
test
test_precedence";
  version = "0.2.37
1.0.80
2.0.105
2
1.0.80
1.0.35
2.0.105";
  src = ././vendor/prettyplease-0.2.37;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "prettyplease
prettyplease
test
test_precedence";
  #   license = lib.licenses.mit;
  # };
}
