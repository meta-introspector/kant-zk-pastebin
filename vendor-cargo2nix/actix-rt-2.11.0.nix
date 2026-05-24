{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "actix-rt
actix_rt
multi_thread_system
test-macro-import-conflict
tests";
  version = "2.11.0
0.2.3
0.3
1.44.2
1.44.2
0.5";
  src = ././vendor/actix-rt-2.11.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "actix-rt
actix_rt
multi_thread_system
test-macro-import-conflict
tests";
  #   license = lib.licenses.mit;
  # };
}
