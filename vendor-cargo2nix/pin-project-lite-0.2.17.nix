{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "pin-project-lite
pin_project_lite
compiletest
drop_order
expandtest
proper_unpin
test";
  version = "0.2.17
1
1";
  src = ././vendor/pin-project-lite-0.2.17;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "pin-project-lite
pin_project_lite
compiletest
drop_order
expandtest
proper_unpin
test";
  #   license = lib.licenses.mit;
  # };
}
