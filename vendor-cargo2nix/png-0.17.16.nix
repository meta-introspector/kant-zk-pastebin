{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "png
png
change-png-info
corpus-bench
png-generate
pngcheck
show
decoder
expand_paletted
unfilter";
  version = "0.17.16
1.0
1.2.0
0.3.3
1.0.11
0.8
0.5.1
1.5.0
3.0
0.4.0
0.2.14
0.32
0.3
0.8.4
1.0.1";
  src = ././vendor/png-0.17.16;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "png
png
change-png-info
corpus-bench
png-generate
pngcheck
show
decoder
expand_paletted
unfilter";
  #   license = lib.licenses.mit;
  # };
}
