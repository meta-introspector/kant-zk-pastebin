{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "anstyle-wincon
anstyle_wincon
dump-wincon
set-wincon";
  version = "3.0.11
1.0.0
0.3.1
1.56.1
>=0.60.2, <0.62";
  src = ././vendor/anstyle-wincon-3.0.11;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "anstyle-wincon
anstyle_wincon
dump-wincon
set-wincon";
  #   license = lib.licenses.mit;
  # };
}
