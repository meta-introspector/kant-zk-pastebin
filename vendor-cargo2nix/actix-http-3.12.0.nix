{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "actix-http
actix_http
actix-web
bench
echo
echo2
h2c-detect
h2spec
hello-world
streaming-error
tls_rustls
ws
test_client
test_h2_timer
test_openssl
test_rustls
test_server
test_ws
date-formatting
response-body-compression";
  version = "3.12.0
0.5
2.2
2
3.4
3
0.22
2
8
1
1
2
0.8
1.0.13
0.1
0.3.17
0.3.27
0.2.7
1.5.1
1.0.1
1
0.3
0.1
0.3.4
2.1
0.2
0.9
0.10
1.6.1
1.38.2
0.7
0.1.30
0.13
3
2
3.4
4
0.3
0.5
0.1.8
0.11
0.3.17
2.4
1.21
0.13
1.3
1.13.1
1
1
1.0
1
0.10.55
0.23
1.38.2";
  src = ././vendor/actix-http-3.12.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "actix-http
actix_http
actix-web
bench
echo
echo2
h2c-detect
h2spec
hello-world
streaming-error
tls_rustls
ws
test_client
test_h2_timer
test_openssl
test_rustls
test_server
test_ws
date-formatting
response-body-compression";
  #   license = lib.licenses.mit;
  # };
}
