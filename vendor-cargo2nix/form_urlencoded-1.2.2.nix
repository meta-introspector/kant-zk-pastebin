{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "form_urlencoded
form_urlencoded";
  version = "1.2.2
2.3.0";
  src = ././vendor/form_urlencoded-1.2.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "form_urlencoded
form_urlencoded";
  #   license = lib.licenses.mit;
  # };
}
