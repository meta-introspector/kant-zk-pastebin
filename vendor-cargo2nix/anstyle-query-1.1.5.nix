{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "anstyle-query
anstyle_query
query";
  version = "1.1.5
>=0.60.2, <0.62";
  src = ././vendor/anstyle-query-1.1.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "anstyle-query
anstyle_query
query";
  #   license = lib.licenses.mit;
  # };
}
