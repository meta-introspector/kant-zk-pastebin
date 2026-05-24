{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "r-efi
r_efi
freestanding
gop-query
hello-world";
  version = "5.3.0
1.0.0";
  src = ././vendor/r-efi-5.3.0;
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
