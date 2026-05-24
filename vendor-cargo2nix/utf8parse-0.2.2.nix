{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "utf8parse
utf8parse
utf-8-demo";
  version = "0.2.2";
  src = ././vendor/utf8parse-0.2.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "utf8parse
utf8parse
utf-8-demo";
  #   license = lib.licenses.mit;
  # };
}
