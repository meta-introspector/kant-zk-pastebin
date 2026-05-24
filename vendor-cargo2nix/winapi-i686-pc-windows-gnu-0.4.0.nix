{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "winapi-i686-pc-windows-gnu";
  version = "0.4.0";
  src = ././vendor/winapi-i686-pc-windows-gnu-0.4.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "winapi-i686-pc-windows-gnu";
  #   license = lib.licenses.mit;
  # };
}
