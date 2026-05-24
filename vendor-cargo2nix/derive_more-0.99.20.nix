{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "derive_more
derive_more
deny_missing_docs
add
add_assign
as_mut
as_ref
boats_display_derive
constructor
deref
deref_mut
display
error
from
from_str
generics
index
index_mut
into
into_iterator
is_variant
lib
mul
mul_assign
no_std
not
sum
try_into
unwrap";
  version = "0.99.20
0.4
1.0
1.0
2
0.5
0.4";
  src = ././vendor/derive_more-0.99.20;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "derive_more
derive_more
deny_missing_docs
add
add_assign
as_mut
as_ref
boats_display_derive
constructor
deref
deref_mut
display
error
from
from_str
generics
index
index_mut
into
into_iterator
is_variant
lib
mul
mul_assign
no_std
not
sum
try_into
unwrap";
  #   license = lib.licenses.mit;
  # };
}
