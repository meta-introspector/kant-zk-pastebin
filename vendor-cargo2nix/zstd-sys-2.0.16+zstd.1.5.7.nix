{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "zstd-sys
zstd_sys";
  version = "2.0.16+zstd.1.5.7
0.72
1.0.45
0.3.28";
  src = ././vendor/zstd-sys-2.0.16+zstd.1.5.7;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "zstd-sys
zstd_sys";
  #   license = lib.licenses.mit;
  # };
}
