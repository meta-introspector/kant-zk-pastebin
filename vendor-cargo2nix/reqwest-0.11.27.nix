{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "reqwest
blocking
json_dynamic
json_typed
tor_socks
form
simple
blocking
cookie
gzip
brotli
deflate
multipart";
  version = "0.11.27
0.21
1.0
0.3.0
0.3.0
0.2
2.0
1.0
1.0
0.7.1
0.1.2
0.3
2.2
0.4.0
0.17.0
0.20.0
0.8
0.3
0.3.14
0.0.3
0.0.4
0.24
0.4.0
0.14.21
0.24.0
0.5
2.3
0.4
0.3.16
0.2.10
1
2.1
0.2.0
0.10
0.21.6
0.6
1.0
1.0
0.3.0
0.24
0.5.1
0.7.1
0.25
3.3.0
0.3
0.10
0.3.0
0.14
1.0
1.0
1.0
0.3.45
1.0
0.2.68
0.4.18
0.4
0.3.25
0.2.68
0.3
0.5.1
0.50.0";
  src = ././vendor/reqwest-0.11.27;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "reqwest
blocking
json_dynamic
json_typed
tor_socks
form
simple
blocking
cookie
gzip
brotli
deflate
multipart";
  #   license = lib.licenses.mit;
  # };
}
