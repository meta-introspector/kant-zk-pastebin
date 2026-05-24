{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "flate2
flate2
compress_file
decompress_file
deflatedecoder-bufread
deflatedecoder-read
deflatedecoder-write
deflateencoder-bufread
deflateencoder-read
deflateencoder-write
gzbuilder
gzdecoder-bufread
gzdecoder-read
gzdecoder-write
gzencoder-bufread
gzencoder-read
gzencoder-write
gzmultidecoder-bufread
gzmultidecoder-read
zlibdecoder-bufread
zlibdecoder-read
zlibdecoder-write
zlibencoder-bufread
zlibencoder-read
zlibencoder-write
capabilities
early-flush
empty-read
gunzip
zero-write";
  version = "1.1.9
0.3.6
1.2.0
0.2
1.1.16
1.1.20
0.8.5
0.6.0
0.3
1.0
0.9
0.8.5";
  src = ././vendor/flate2-1.1.9;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "flate2
flate2
compress_file
decompress_file
deflatedecoder-bufread
deflatedecoder-read
deflatedecoder-write
deflateencoder-bufread
deflateencoder-read
deflateencoder-write
gzbuilder
gzdecoder-bufread
gzdecoder-read
gzdecoder-write
gzencoder-bufread
gzencoder-read
gzencoder-write
gzmultidecoder-bufread
gzmultidecoder-read
zlibdecoder-bufread
zlibdecoder-read
zlibdecoder-write
zlibencoder-bufread
zlibencoder-read
zlibencoder-write
capabilities
early-flush
empty-read
gunzip
zero-write";
  #   license = lib.licenses.mit;
  # };
}
