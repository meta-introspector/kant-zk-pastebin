{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "env_logger
regexp_filter
log-in-log
log_tls_dtors
init-twice-retains-filter";
  version = "0.7.1
0.2.5
1.3
0.4.8
1.0.3
1.0.2";
  src = ././vendor/env_logger-0.7.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "env_logger
regexp_filter
log-in-log
log_tls_dtors
init-twice-retains-filter";
  #   license = lib.licenses.mit;
  # };
}
