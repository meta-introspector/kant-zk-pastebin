{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "rustc_version
rustc_version
all";
  version = "0.4.1
1.0
0.3";
  src = ././vendor/rustc_version-0.4.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "rustc_version
rustc_version
all";
  #   license = lib.licenses.mit;
  # };
}
