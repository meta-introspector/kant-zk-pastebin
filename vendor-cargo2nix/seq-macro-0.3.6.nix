{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "seq-macro
seq_macro
compiletest
test";
  version = "0.3.6
1.0
1.0.49";
  src = ././vendor/seq-macro-0.3.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "seq-macro
seq_macro
compiletest
test";
  #   license = lib.licenses.mit;
  # };
}
