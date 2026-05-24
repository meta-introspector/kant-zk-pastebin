{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "winapi-x86_64-pc-windows-gnu";
  version = "0.4.0";
  src = ././vendor/winapi-x86_64-pc-windows-gnu-0.4.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "winapi-x86_64-pc-windows-gnu";
  #   license = lib.licenses.mit;
  # };
}
