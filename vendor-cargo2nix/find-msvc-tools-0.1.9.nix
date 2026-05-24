{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "find-msvc-tools
find_msvc_tools";
  version = "0.1.9";
  src = ././vendor/find-msvc-tools-0.1.9;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "find-msvc-tools
find_msvc_tools";
  #   license = lib.licenses.mit;
  # };
}
