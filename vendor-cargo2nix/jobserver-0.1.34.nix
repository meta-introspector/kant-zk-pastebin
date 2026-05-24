{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "jobserver
jobserver
client
client-of-myself
helper
make-as-a-client
server";
  version = "0.1.34
3.10.1
0.2.171
0.28.0
0.3.2";
  src = ././vendor/jobserver-0.1.34;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "jobserver
jobserver
client
client-of-myself
helper
make-as-a-client
server";
  #   license = lib.licenses.mit;
  # };
}
