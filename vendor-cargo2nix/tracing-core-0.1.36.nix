{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "tracing-core
tracing_core
dispatch
global_dispatch
local_dispatch_before_init
macros
missed_register_callsite";
  version = "0.1.36
1.13.0
0.1.0";
  src = ././vendor/tracing-core-0.1.36;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "tracing-core
tracing_core
dispatch
global_dispatch
local_dispatch_before_init
macros
missed_register_callsite";
  #   license = lib.licenses.mit;
  # };
}
