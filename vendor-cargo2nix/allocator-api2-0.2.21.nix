{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "allocator-api2
allocator_api2";
  version = "0.2.21
1.0";
  src = ././vendor/allocator-api2-0.2.21;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "allocator-api2
allocator_api2";
  #   license = lib.licenses.mit;
  # };
}
