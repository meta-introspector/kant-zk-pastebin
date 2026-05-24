{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "id-arena
id_arena
readme_up_to_date";
  version = "2.3.0
1.0.3";
  src = ././vendor/id-arena-2.3.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "id-arena
id_arena
readme_up_to_date";
  #   license = lib.licenses.mit;
  # };
}
