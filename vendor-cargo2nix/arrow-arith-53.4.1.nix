{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "arrow-arith
arrow_arith";
  version = "53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
>= 0.4.34, < 0.4.40
2.1
0.4";
  src = ././vendor/arrow-arith-53.4.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "arrow-arith
arrow_arith";
  #   license = lib.licenses.mit;
  # };
}
