{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "tracing
tracing
enabled
event
filter_caching_is_lexically_scoped
filters_are_not_reevaluated_for_the_same_span
filters_are_reevaluated_for_different_call_sites
filters_dont_leak
future_send
instrument
macro_imports
macros
macros_incompatible_concat
max_level_hint
missed_register_callsite
multiple_max_level_hints
no_subscriber
register_callsite_deadlock
scoped_clobbers_default
span
subscriber
baseline
dispatch_get_clone
dispatch_get_ref
empty_span
enter_span
event
shared
span_fields
span_no_fields
span_repeated";
  version = "0.1.44
0.4.17
0.2.9
0.1.31
0.1.36
0.3.6
0.3.21
0.4.17
0.3.38";
  src = ././vendor/tracing-0.1.44;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "tracing
tracing
enabled
event
filter_caching_is_lexically_scoped
filters_are_not_reevaluated_for_the_same_span
filters_are_reevaluated_for_different_call_sites
filters_dont_leak
future_send
instrument
macro_imports
macros
macros_incompatible_concat
max_level_hint
missed_register_callsite
multiple_max_level_hints
no_subscriber
register_callsite_deadlock
scoped_clobbers_default
span
subscriber
baseline
dispatch_get_clone
dispatch_get_ref
empty_span
enter_span
event
shared
span_fields
span_no_fields
span_repeated";
  #   license = lib.licenses.mit;
  # };
}
