{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "yaxpeax-arch";
  version = "0.3.2
0.27.0
0.2
1.0
1.0
1.0.41
1.0.26";
  src = ././vendor/yaxpeax-arch-0.3.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "yaxpeax-arch";
  #   license = lib.licenses.mit;
  # };
}
