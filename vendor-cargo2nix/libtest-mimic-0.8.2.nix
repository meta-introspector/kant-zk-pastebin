{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "libtest-mimic
libtest_mimic
simple
tidy
all_passing
mixed_bag
panic
threads";
  version = "0.8.2
1
1.0.7
4.0.8
0.5.2
2.0.0
1.2.1";
  src = ././vendor/libtest-mimic-0.8.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "libtest-mimic
libtest_mimic
simple
tidy
all_passing
mixed_bag
panic
threads";
  #   license = lib.licenses.mit;
  # };
}
