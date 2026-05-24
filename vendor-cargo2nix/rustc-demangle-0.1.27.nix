{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "rustc-demangle
rustc_demangle";
  version = "0.1.27
1.0.0";
  src = ././vendor/rustc-demangle-0.1.27;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "rustc-demangle
rustc_demangle";
  #   license = lib.licenses.mit;
  # };
}
