{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "jiff-static
jiff_static";
  version = "0.2.23
0.1.6
1.0.93
1.0.38
2.0.98";
  src = ././vendor/jiff-static-0.2.23;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "jiff-static
jiff_static";
  #   license = lib.licenses.mit;
  # };
}
