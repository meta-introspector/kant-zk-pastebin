{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "winapi-util
winapi_util";
  version = "0.1.11
>=0.48.0, <=0.61.*";
  src = ././vendor/winapi-util-0.1.11;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "winapi-util
winapi_util";
  #   license = lib.licenses.mit;
  # };
}
