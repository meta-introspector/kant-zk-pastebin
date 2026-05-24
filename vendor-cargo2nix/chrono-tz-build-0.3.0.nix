{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "chrono-tz-build";
  version = "0.3.0
0.3
0.11
0.11
1
0.9";
  src = ././vendor/chrono-tz-build-0.3.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "chrono-tz-build";
  #   license = lib.licenses.mit;
  # };
}
