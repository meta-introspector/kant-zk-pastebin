{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "parking_lot_core
parking_lot_core";
  version = "0.9.12
0.3.60
1.0.0
0.6.0
1.6.1
0.5
0.2.95
0.2.0";
  src = ././vendor/parking_lot_core-0.9.12;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "parking_lot_core
parking_lot_core";
  #   license = lib.licenses.mit;
  # };
}
