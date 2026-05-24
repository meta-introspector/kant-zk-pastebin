{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "r-efi
r_efi
freestanding
gop-query
hello-world";
  version = "6.0.0
1.0.0";
  src = ././vendor/r-efi-6.0.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "r-efi
r_efi
freestanding
gop-query
hello-world";
  #   license = lib.licenses.mit;
  # };
}
