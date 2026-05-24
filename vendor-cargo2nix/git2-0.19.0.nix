{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "git2";
  version = "0.19.0
2.1.0
0.2
0.17.0
0.4.8
2.0
4.4.13
3.1.0
0.1.39
0.1
0.9.45";
  src = ././vendor/git2-0.19.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "git2";
  #   license = lib.licenses.mit;
  # };
}
