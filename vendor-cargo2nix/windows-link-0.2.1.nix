{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "windows-link
windows_link";
  version = "0.2.1";
  src = ././vendor/windows-link-0.2.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "windows-link
windows_link";
  #   license = lib.licenses.mit;
  # };
}
