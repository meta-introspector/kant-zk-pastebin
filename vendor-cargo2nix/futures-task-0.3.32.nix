{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "futures-task
futures_task";
  version = "0.3.32";
  src = ././vendor/futures-task-0.3.32;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "futures-task
futures_task";
  #   license = lib.licenses.mit;
  # };
}
