{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "libbpf-rs
libbpf_rs
test
test_netfilter
test_print
test_tc
test_xdp";
  version = "0.24.8
2.0
1.4.1
0.2
2.0
1.0.3
0.3.3
0.4.4
0.1.1
0.2.3
0.3
1.1
3.0
3.3
0.1
1.4.1
3.3";
  src = ././vendor/libbpf-rs-0.24.8;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "libbpf-rs
libbpf_rs
test
test_netfilter
test_print
test_tc
test_xdp";
  #   license = lib.licenses.mit;
  # };
}
