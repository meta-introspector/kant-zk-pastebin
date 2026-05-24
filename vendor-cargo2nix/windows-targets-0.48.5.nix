{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "windows-targets";
  version = "0.48.5
0.48.5
0.48.5
0.48.5
0.48.5
0.48.5
0.48.5
0.48.5";
  src = ././vendor/windows-targets-0.48.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "windows-targets";
  #   license = lib.licenses.mit;
  # };
}
