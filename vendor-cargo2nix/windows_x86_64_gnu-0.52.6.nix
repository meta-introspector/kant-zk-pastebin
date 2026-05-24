{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "windows_x86_64_gnu
windows_x86_64_gnu";
  version = "0.52.6";
  src = ././vendor/windows_x86_64_gnu-0.52.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "windows_x86_64_gnu
windows_x86_64_gnu";
  #   license = lib.licenses.mit;
  # };
}
