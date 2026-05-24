{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "typed-arena
typed_arena
benches";
  version = "2.0.2
0.3.4";
  src = ././vendor/typed-arena-2.0.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "typed-arena
typed_arena
benches";
  #   license = lib.licenses.mit;
  # };
}
