{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "android-tzdata";
  version = "0.1.1
0.6.4";
  src = ././vendor/android-tzdata-0.1.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "android-tzdata";
  #   license = lib.licenses.mit;
  # };
}
