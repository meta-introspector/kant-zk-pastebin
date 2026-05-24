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
compile_fail
constructor
debug
deref
deref_mut
display
eq
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
partial_eq
sum
try_from
try_into
try_unwrap
unwrap";
  version = "2.1.1
=2.1.1
1.0
1.1
1.0.56
0.4";
  src = ././vendor/derive_more-2.1.1;
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
compile_fail
constructor
debug
deref
deref_mut
display
eq
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
partial_eq
sum
try_from
try_into
try_unwrap
unwrap";
  #   license = lib.licenses.mit;
  # };
}
