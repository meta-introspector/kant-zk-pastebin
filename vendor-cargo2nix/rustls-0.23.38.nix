{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "rustls
rustls
test_ca
benchmarks";
  version = "0.23.38
1.14
8
5.0.0
0.15
0.4.8
1.16
1.12
0.17
2.5.0
0.103.5
1.8
0.6
0.22
0.1.5
0.11
0.4
0.4.8
0.2
0.4.4
0.14
1
1
0.3.6
1
0.17
1.0.6";
  src = ././vendor/rustls-0.23.38;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "rustls
rustls
test_ca
benchmarks";
  #   license = lib.licenses.mit;
  # };
}
