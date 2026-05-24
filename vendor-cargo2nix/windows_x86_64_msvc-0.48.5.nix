{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "windows_x86_64_msvc";
  version = "0.48.5";
  src = ././vendor/windows_x86_64_msvc-0.48.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "windows_x86_64_msvc";
  #   license = lib.licenses.mit;
  # };
}
