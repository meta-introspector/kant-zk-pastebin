{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "windows_x86_64_gnu";
  version = "0.48.5";
  src = ././vendor/windows_x86_64_gnu-0.48.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "windows_x86_64_gnu";
  #   license = lib.licenses.mit;
  # };
}
