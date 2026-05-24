{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "num-bigint
bigint
factorial
gcd
roots
shootout-pidigits";
  version = "0.4.6
1
0.1.46
0.2.18
1
0.8
1.0";
  src = ././vendor/num-bigint-0.4.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "num-bigint
bigint
factorial
gcd
roots
shootout-pidigits";
  #   license = lib.licenses.mit;
  # };
}
