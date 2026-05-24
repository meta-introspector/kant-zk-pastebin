{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "ureq
ureq
count-bytes
cureq
custom-tls
ipv6
smoke-test
tls_config
https-agent";
  version = "2.12.1
0.22
4.0.0
0.18
0.21.1
0.8
1.0.22
0.1.5
1.1
0.2
0.4
0.2
1
0.23.19
0.7
1
1
1.0.97
0.3
2.5.0
0.26
<=0.9
0.23.5
2.0
1";
  src = ././vendor/ureq-2.12.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "ureq
ureq
count-bytes
cureq
custom-tls
ipv6
smoke-test
tls_config
https-agent";
  #   license = lib.licenses.mit;
  # };
}
