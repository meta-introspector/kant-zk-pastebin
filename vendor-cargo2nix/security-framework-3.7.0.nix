{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "security-framework
security_framework
client
find_internet_password
set_internet_password";
  version = "3.7.0
2.11
0.10
0.8.6
0.2.139
0.4.20
2.17
0.11
0.4.3
3.12.0
0.3.23
0.18";
  src = ././vendor/security-framework-3.7.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "security-framework
security_framework
client
find_internet_password
set_internet_password";
  #   license = lib.licenses.mit;
  # };
}
