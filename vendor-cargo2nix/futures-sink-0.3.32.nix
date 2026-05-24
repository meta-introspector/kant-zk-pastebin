{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "futures-sink
futures_sink";
  version = "0.3.32";
  src = ././vendor/futures-sink-0.3.32;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "futures-sink
futures_sink";
  #   license = lib.licenses.mit;
  # };
}
