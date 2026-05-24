{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "actix-web
actix_web
basic
from_fn
introspection
introspection_multi_servers
macroless
middleware_from_fn
on-connect
uds
worker-cpu-pin
compression
introspection
test-macro-import-conflict
test_error_propagation
test_httpserver
test_server
test_streaming_response
test_weird_poll
utils
weird_poll
responder
server
service";
  version = "4.13.0
0.5
3.12.0
0.2.3
0.5.4
2.6
2.6
2
3.4
3
4.3
1
1
1
0.16
2
0.8
0.1
0.3.17
0.3.17
0.1.4
1
0.3
0.4
0.3
1.21
0.2.7
1.5.5
0.1
1.0
1.0
0.7
1.6.1
0.6
0.3
0.1.30
2.5.4
0.6
0.1
3
8
0.5
0.8
0.5
0.11
1.0.13
0.3.17
0.9
0.13
1.13.1
1
1
0.10.55
0.23
1.38.2
0.7
0.13";
  src = ././vendor/actix-web-4.13.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "actix-web
actix_web
basic
from_fn
introspection
introspection_multi_servers
macroless
middleware_from_fn
on-connect
uds
worker-cpu-pin
compression
introspection
test-macro-import-conflict
test_error_propagation
test_httpserver
test_server
test_streaming_response
test_weird_poll
utils
weird_poll
responder
server
service";
  #   license = lib.licenses.mit;
  # };
}
