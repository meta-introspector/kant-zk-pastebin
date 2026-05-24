{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "native-tls
native_tls";
  version = "0.2.18
3.0
0.9
0.4.27
0.10.75
0.2.1
0.9.111
3.1.0
0.1.28
0.2.170
3.5.1
2.15.0";
  src = ././vendor/native-tls-0.2.18;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "native-tls
native_tls";
  #   license = lib.licenses.mit;
  # };
}
