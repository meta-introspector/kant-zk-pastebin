{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "proc-macro-error-attr";
  version = "1.0.4
1
1
0.9";
  src = ././vendor/proc-macro-error-attr-1.0.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "proc-macro-error-attr";
  #   license = lib.licenses.mit;
  # };
}
