{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "tempfile
tempfile
env
namedtempfile
spooled
tempdir
tempfile";
  version = "3.27.0
2.1.1
1.19.0
0.3
1.1.4
>=0.3.0, <0.5
>=0.52, <0.62";
  src = ././vendor/tempfile-3.27.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "tempfile
tempfile
env
namedtempfile
spooled
tempdir
tempfile";
  #   license = lib.licenses.mit;
  # };
}
