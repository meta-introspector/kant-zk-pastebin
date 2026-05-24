{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "futures-io
futures_io";
  version = "0.3.32";
  src = ././vendor/futures-io-0.3.32;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "futures-io
futures_io";
  #   license = lib.licenses.mit;
  # };
}
