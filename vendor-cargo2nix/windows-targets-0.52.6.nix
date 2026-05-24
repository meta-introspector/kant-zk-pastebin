{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "windows-targets
windows_targets";
  version = "0.52.6
0.52.6
0.52.6
0.52.6
0.52.6
0.52.6
0.52.6
0.52.6
0.52.6";
  src = ././vendor/windows-targets-0.52.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "windows-targets
windows_targets";
  #   license = lib.licenses.mit;
  # };
}
