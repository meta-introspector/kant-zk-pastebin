{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "unicode-xid
unicode_xid
exhaustive_tests
xid";
  version = "0.2.6
0.3";
  src = ././vendor/unicode-xid-0.2.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "unicode-xid
unicode_xid
exhaustive_tests
xid";
  #   license = lib.licenses.mit;
  # };
}
