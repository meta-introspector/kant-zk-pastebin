{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "mio
mio
tcp_listenfd_server
tcp_server
udp_server";
  version = "1.2.0
0.4.8
0.11
0.9
0.2.183
0.11.0
0.61";
  src = ././vendor/mio-1.2.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "mio
mio
tcp_listenfd_server
tcp_server
udp_server";
  #   license = lib.licenses.mit;
  # };
}
