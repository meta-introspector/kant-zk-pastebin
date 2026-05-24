{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "arrow-cast
arrow_cast
parse_date
parse_decimal
parse_time
parse_timestamp";
  version = "53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
2.0.0
0.22
>= 0.4.34, < 0.4.40
7.0
2.1
1.0
0.4
1.0.16
0.5
2.1
0.8";
  src = ././vendor/arrow-cast-53.4.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "arrow-cast
arrow_cast
parse_date
parse_decimal
parse_time
parse_timestamp";
  #   license = lib.licenses.mit;
  # };
}
