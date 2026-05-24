{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "bytemuck
bytemuck
array_tests
cast_slice_tests
checked_tests
derive
doc_tests
offset_of_tests
std_tests
transparent
wrapper_forgets";
  version = "1.25.0
1.10.2
1.0.22";
  src = ././vendor/bytemuck-1.25.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "bytemuck
bytemuck
array_tests
cast_slice_tests
checked_tests
derive
doc_tests
offset_of_tests
std_tests
transparent
wrapper_forgets";
  #   license = lib.licenses.mit;
  # };
}
