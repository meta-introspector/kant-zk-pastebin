{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "proc-macro-error";
  version = "1.0.4
=1.0.4
1
1
1
=1.0.107
=0.5.2
1.0.19
0.9";
  src = ././vendor/proc-macro-error-1.0.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "proc-macro-error";
  #   license = lib.licenses.mit;
  # };
}
