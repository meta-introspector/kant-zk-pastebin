{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "dyn-clone
dyn_clone
readme
compiletest
macros
trait";
  version = "1.0.20
1.0
1.0.66";
  src = ././vendor/dyn-clone-1.0.20;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "dyn-clone
dyn_clone
readme
compiletest
macros
trait";
  #   license = lib.licenses.mit;
  # };
}
