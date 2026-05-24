{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "windows_aarch64_gnullvm";
  version = "0.48.5";
  src = ././vendor/windows_aarch64_gnullvm-0.48.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "windows_aarch64_gnullvm";
  #   license = lib.licenses.mit;
  # };
}
