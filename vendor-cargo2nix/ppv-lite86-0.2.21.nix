{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "ppv-lite86
ppv_lite86";
  version = "0.2.21
0.8.23";
  src = ././vendor/ppv-lite86-0.2.21;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "ppv-lite86
ppv_lite86";
  #   license = lib.licenses.mit;
  # };
}
