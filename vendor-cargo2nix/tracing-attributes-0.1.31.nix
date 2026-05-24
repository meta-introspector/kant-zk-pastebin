{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "tracing-attributes
tracing_attributes
async_fn
dead_code
destructuring
err
fields
follows_from
instrument
levels
names
parents
ret
targets
ui";
  version = "0.1.31
1.0.60
1.0.20
2.0
0.1.67
1.0.9
0.4.2
0.1.35
0.3.0
1.0.64";
  src = ././vendor/tracing-attributes-0.1.31;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "tracing-attributes
tracing_attributes
async_fn
dead_code
destructuring
err
fields
follows_from
instrument
levels
names
parents
ret
targets
ui";
  #   license = lib.licenses.mit;
  # };
}
