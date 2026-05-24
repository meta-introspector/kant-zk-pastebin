{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "pkg-config
pkg_config
test";
  version = "0.3.33
1";
  src = ././vendor/pkg-config-0.3.33;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "pkg-config
pkg_config
test";
  #   license = lib.licenses.mit;
  # };
}
