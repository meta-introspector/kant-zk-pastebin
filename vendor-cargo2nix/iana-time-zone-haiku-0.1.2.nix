{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "iana-time-zone-haiku";
  version = "0.1.2
1.0.79";
  src = ././vendor/iana-time-zone-haiku-0.1.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "iana-time-zone-haiku";
  #   license = lib.licenses.mit;
  # };
}
