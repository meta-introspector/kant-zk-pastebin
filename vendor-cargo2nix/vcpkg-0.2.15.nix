{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "vcpkg";
  version = "0.2.15
1
0.3.7";
  src = ././vendor/vcpkg-0.2.15;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "vcpkg";
  #   license = lib.licenses.mit;
  # };
}
