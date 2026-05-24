{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "zstd
zstd
basic
benchmark
stream
train
zstd
zstdcat
issue_182";
  version = "0.13.3
7.1.0
4.0
2.0
0.5
2.2";
  src = ././vendor/zstd-0.13.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "zstd
zstd
basic
benchmark
stream
train
zstd
zstdcat
issue_182";
  #   license = lib.licenses.mit;
  # };
}
