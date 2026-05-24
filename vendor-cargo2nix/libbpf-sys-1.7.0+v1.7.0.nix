{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "libbpf-sys
libbpf_sys
tests";
  version = "1.7.0+v1.7.0
^0.72.0
^1.2.27
^0.31.2
^0.3.32";
  src = ././vendor/libbpf-sys-1.7.0+v1.7.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "libbpf-sys
libbpf_sys
tests";
  #   license = lib.licenses.mit;
  # };
}
