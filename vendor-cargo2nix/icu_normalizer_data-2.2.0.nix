{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "icu_normalizer_data
icu_normalizer_data";
  version = "2.2.0";
  src = ././vendor/icu_normalizer_data-2.2.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "icu_normalizer_data
icu_normalizer_data";
  #   license = lib.licenses.mit;
  # };
}
