{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "env_logger
env_logger
custom_default_format
custom_format
default
direct_logger
filters_from_code
in_tests
syslog_friendly_format";
  version = "0.11.10
1.0.0
1.0.13
1.0.0
0.2.22
0.4.29";
  src = ././vendor/env_logger-0.11.10;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "env_logger
env_logger
custom_default_format
custom_format
default
direct_logger
filters_from_code
in_tests
syslog_friendly_format";
  #   license = lib.licenses.mit;
  # };
}
