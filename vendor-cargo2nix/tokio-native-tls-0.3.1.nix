{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "tokio-native-tls";
  version = "0.3.1
0.2
1.0
0.1
0.6
0.3.0
1.4.0
3.1
1.0
0.6.0
0.10
0.2
0.1
0.3";
  src = ././vendor/tokio-native-tls-0.3.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "tokio-native-tls";
  #   license = lib.licenses.mit;
  # };
}
