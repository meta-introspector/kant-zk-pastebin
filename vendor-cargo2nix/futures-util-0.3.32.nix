{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "futures-util
futures_util
bilock
flatten_unordered
futures_unordered
select";
  version = "0.3.32
0.3.32
0.3.32
0.3.32
=0.3.32
0.3.32
0.3.32
0.1.25
0.2.26
2.2
0.2.6
0.4.7
0.10.0
0.1.9
0.1.11";
  src = ././vendor/futures-util-0.3.32;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "futures-util
futures_util
bilock
flatten_unordered
futures_unordered
select";
  #   license = lib.licenses.mit;
  # };
}
