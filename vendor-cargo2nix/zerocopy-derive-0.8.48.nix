{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "zerocopy-derive
zerocopy_derive
deprecated
enum_from_zeros
enum_known_layout
enum_no_cell
enum_to_bytes
enum_try_from_bytes
enum_unaligned
eq
hash
hygiene
include
issue_2117
issue_2835
issue_2880
issue_2915
on_error
paths_and_modules
priv_in_pub
struct_from_bytes
struct_from_zeros
struct_known_layout
struct_no_cell
struct_to_bytes
struct_try_from_bytes
struct_unaligned
ui
union_from_bytes
union_from_zeros
union_known_layout
union_no_cell
union_to_bytes
union_try_from_bytes
union_unaligned
unsafe_cell";
  version = "0.8.48
1.0.1
1.0.40
2.0.46
1.0.9
=0.2.17
1.0
1.1
2.0.46";
  src = ././vendor/zerocopy-derive-0.8.48;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "zerocopy-derive
zerocopy_derive
deprecated
enum_from_zeros
enum_known_layout
enum_no_cell
enum_to_bytes
enum_try_from_bytes
enum_unaligned
eq
hash
hygiene
include
issue_2117
issue_2835
issue_2880
issue_2915
on_error
paths_and_modules
priv_in_pub
struct_from_bytes
struct_from_zeros
struct_known_layout
struct_no_cell
struct_to_bytes
struct_try_from_bytes
struct_unaligned
ui
union_from_bytes
union_from_zeros
union_known_layout
union_no_cell
union_to_bytes
union_try_from_bytes
union_unaligned
unsafe_cell";
  #   license = lib.licenses.mit;
  # };
}
