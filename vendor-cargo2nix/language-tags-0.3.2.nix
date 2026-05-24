{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "language-tags
language_tag";
  version = "0.3.2
1.0
0.1
1.0";
  src = ././vendor/language-tags-0.3.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "language-tags
language_tag";
  #   license = lib.licenses.mit;
  # };
}
