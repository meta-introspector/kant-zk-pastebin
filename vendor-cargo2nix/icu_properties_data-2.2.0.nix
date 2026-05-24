{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "icu_properties_data
icu_properties_data";
  version = "2.2.0";
  src = ././vendor/icu_properties_data-2.2.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "icu_properties_data
icu_properties_data";
  #   license = lib.licenses.mit;
  # };
}
