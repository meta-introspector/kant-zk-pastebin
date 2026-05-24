{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "linux-raw-sys
linux_raw_sys";
  version = "0.12.1
1.0.0
0.2.100
1.1.0";
  src = ././vendor/linux-raw-sys-0.12.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "linux-raw-sys
linux_raw_sys";
  #   license = lib.licenses.mit;
  # };
}
