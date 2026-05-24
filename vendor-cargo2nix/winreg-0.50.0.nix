{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "winreg
basic_usage
enum
load_app_key
transactions
serialization
map_key_serialization
installed_apps";
  version = "0.50.0
1.0
0.4.6
1
0.48.0
0.3
0.11
1
~3.0";
  src = ././vendor/winreg-0.50.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "winreg
basic_usage
enum
load_app_key
transactions
serialization
map_key_serialization
installed_apps";
  #   license = lib.licenses.mit;
  # };
}
