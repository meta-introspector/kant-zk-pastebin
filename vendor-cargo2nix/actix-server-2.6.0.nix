{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "actix-server
actix_server
file-reader
shutdown-signal
tcp-echo
server
testing_server";
  version = "2.6.0
2.10
2
3
0.3.17
0.3.17
1
0.5
1.44.2
0.1.30
0.5
2.8
1
0.3.17
0.5
1
1.44.2
0.7
0.3
0.5";
  src = ././vendor/actix-server-2.6.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "actix-server
actix_server
file-reader
shutdown-signal
tcp-echo
server
testing_server";
  #   license = lib.licenses.mit;
  # };
}
