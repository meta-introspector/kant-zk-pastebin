{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "winnow
winnow
arithmetic
c_expression
css
custom_error
http
ini
iterator
json
json_iterator
ndjson
s_expression
string
arithmetic
c_expression
http
ini
json";
  version = "1.0.1
0.6.15
1.0.8
1.48.1
2.7
0.4.3
0.11.4
1.0.100
1.0.15
0.3.0
0.5.1
0.3.1
1.6.0
2.1.1
0.6.21
0.2.0";
  src = ././vendor/winnow-1.0.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "winnow
winnow
arithmetic
c_expression
css
custom_error
http
ini
iterator
json
json_iterator
ndjson
s_expression
string
arithmetic
c_expression
http
ini
json";
  #   license = lib.licenses.mit;
  # };
}
