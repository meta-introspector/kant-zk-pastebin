{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "unsafe-libyaml";
  version = "0.2.11
1.0";
  src = ././vendor/unsafe-libyaml-0.2.11;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "unsafe-libyaml";
  #   license = lib.licenses.mit;
  # };
}
