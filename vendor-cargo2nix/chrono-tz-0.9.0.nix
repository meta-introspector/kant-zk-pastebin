{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "chrono-tz";
  version = "0.9.0
1.2
0.4.25
0.11
1.0.99
0.9
0.4
1
0.3";
  src = ././vendor/chrono-tz-0.9.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "chrono-tz";
  #   license = lib.licenses.mit;
  # };
}
