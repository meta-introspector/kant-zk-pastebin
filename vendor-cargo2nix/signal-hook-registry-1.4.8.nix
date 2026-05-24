{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "signal-hook-registry
signal_hook_registry
unregister_signal";
  version = "1.4.8
>=0.2, <0.4
^0.2
~0.3";
  src = ././vendor/signal-hook-registry-1.4.8;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "signal-hook-registry
signal_hook_registry
unregister_signal";
  #   license = lib.licenses.mit;
  # };
}
