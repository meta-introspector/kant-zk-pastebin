{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "criterion
criterion
criterion_tests
bench_main";
  version = "0.8.2
0.1.4
0.3
0.2.0
4.5
0.8.2
1.1
0.3
0.13
0.2
11.1
0.6
^0.3.2
1.3
1.5.1
1.0.100
1.0.100
2.0
1.1
1.0
2.3
0.5.0
0.3
1.0
0.8
3.5.0
0.4";
  src = ././vendor/criterion-0.8.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "criterion
criterion
criterion_tests
bench_main";
  #   license = lib.licenses.mit;
  # };
}
