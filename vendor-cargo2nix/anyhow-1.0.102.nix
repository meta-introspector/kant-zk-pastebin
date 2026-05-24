{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "anyhow
anyhow
compiletest
test_autotrait
test_backtrace
test_boxed
test_chain
test_context
test_convert
test_downcast
test_ensure
test_ffi
test_fmt
test_macros
test_repr
test_source";
  version = "1.0.102
0.3
1.0.6
2.0
2
1.0.108";
  src = ././vendor/anyhow-1.0.102;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "anyhow
anyhow
compiletest
test_autotrait
test_backtrace
test_boxed
test_chain
test_context
test_convert
test_downcast
test_ensure
test_ffi
test_fmt
test_macros
test_repr
test_source";
  #   license = lib.licenses.mit;
  # };
}
