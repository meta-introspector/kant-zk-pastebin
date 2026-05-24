{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "zstd-safe
zstd_safe";
  version = "7.2.4
2.0.15";
  src = ././vendor/zstd-safe-7.2.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "zstd-safe
zstd_safe";
  #   license = lib.licenses.mit;
  # };
}
