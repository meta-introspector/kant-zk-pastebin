{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "derive_more-impl
derive_more_impl";
  version = "2.1.1
0.10
1.0
1.0
2.0.45
0.2.2
0.14.0
0.4";
  src = ././vendor/derive_more-impl-2.1.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "derive_more-impl
derive_more_impl";
  #   license = lib.licenses.mit;
  # };
}
