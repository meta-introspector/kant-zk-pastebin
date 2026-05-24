{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "windows_aarch64_msvc
windows_aarch64_msvc";
  version = "0.52.6";
  src = ././vendor/windows_aarch64_msvc-0.52.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "windows_aarch64_msvc
windows_aarch64_msvc";
  #   license = lib.licenses.mit;
  # };
}
