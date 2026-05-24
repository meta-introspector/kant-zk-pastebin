{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "android_system_properties";
  version = "0.1.5
0.2.126";
  src = ././vendor/android_system_properties-0.1.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "android_system_properties";
  #   license = lib.licenses.mit;
  # };
}
