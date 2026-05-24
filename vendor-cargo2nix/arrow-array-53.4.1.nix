{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "arrow-array
arrow_array
decimal_overflow
fixed_size_list_array
gc_view_types
occupancy
union_array";
  version = "53.4.1
53.4.1
53.4.1
53.4.1
>= 0.4.34, < 0.4.40
0.10
2.1
0.15.1
0.4.1
0.5
0.8
0.8
0.8";
  src = ././vendor/arrow-array-53.4.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "arrow-array
arrow_array
decimal_overflow
fixed_size_list_array
gc_view_types
occupancy
union_array";
  #   license = lib.licenses.mit;
  # };
}
