{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "icu_properties
icu_properties";
  version = "2.2.0
0.2.0
0.6.0
~2.2.0
2.2.0
~2.2.0
2.2.0
1.0.220
0.3.11
0.2.4
0.11.6";
  src = ././vendor/icu_properties-2.2.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "icu_properties
icu_properties";
  #   license = lib.licenses.mit;
  # };
}
