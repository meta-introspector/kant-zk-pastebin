{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "thiserror-impl
thiserror_impl";
  version = "2.0.18
1.0.74
1.0.35
2.0.87";
  src = ././vendor/thiserror-impl-2.0.18;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "thiserror-impl
thiserror_impl";
  #   license = lib.licenses.mit;
  # };
}
