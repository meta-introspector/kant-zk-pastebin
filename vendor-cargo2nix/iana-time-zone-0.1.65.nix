{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "iana-time-zone
iana_time_zone
get_timezone
get_timezone_loop
stress-test";
  version = "0.1.65
0.10.1
0.2.1
0.3.66
0.4.14
0.2.89
0.2.1
0.3.46
0.1.5
0.1.1
>=0.56, <=0.62
0.8.6";
  src = ././vendor/iana-time-zone-0.1.65;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "iana-time-zone
iana_time_zone
get_timezone
get_timezone_loop
stress-test";
  #   license = lib.licenses.mit;
  # };
}
