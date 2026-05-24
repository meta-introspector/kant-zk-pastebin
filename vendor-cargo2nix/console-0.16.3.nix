{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "console
console";
  version = "0.16.3
0.2.99
0.2
1.0.0
1.4.2
1
0.61";
  src = ././vendor/console-0.16.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "console
console";
  #   license = lib.licenses.mit;
  # };
}
