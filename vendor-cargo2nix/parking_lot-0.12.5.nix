{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "parking_lot
parking_lot
issue_203
issue_392";
  version = "0.12.5
0.4.14
0.9.12
1.3.3
0.8.3";
  src = ././vendor/parking_lot-0.12.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "parking_lot
parking_lot
issue_203
issue_392";
  #   license = lib.licenses.mit;
  # };
}
