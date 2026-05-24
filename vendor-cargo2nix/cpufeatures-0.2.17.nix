{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "cpufeatures
cpufeatures
aarch64
loongarch64
x86";
  version = "0.2.17
0.2.155
0.2.155
0.2.155
0.2.155";
  src = ././vendor/cpufeatures-0.2.17;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "cpufeatures
cpufeatures
aarch64
loongarch64
x86";
  #   license = lib.licenses.mit;
  # };
}
