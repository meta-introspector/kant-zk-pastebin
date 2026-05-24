{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "windows-result
windows_result";
  version = "0.4.1
0.2.1";
  src = ././vendor/windows-result-0.4.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "windows-result
windows_result";
  #   license = lib.licenses.mit;
  # };
}
