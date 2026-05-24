{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "windows_aarch64_gnullvm
windows_aarch64_gnullvm";
  version = "0.52.6";
  src = ././vendor/windows_aarch64_gnullvm-0.52.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "windows_aarch64_gnullvm
windows_aarch64_gnullvm";
  #   license = lib.licenses.mit;
  # };
}
