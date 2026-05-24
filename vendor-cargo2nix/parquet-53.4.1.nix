{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "parquet
parquet
parquet-concat
parquet-fromcsv
parquet-index
parquet-layout
parquet-read
parquet-rewrite
parquet-rowcount
parquet-schema
parquet-show-bloom-filter
async_read_parquet
external_metadata
read_parquet
read_with_rowgroup
write_parquet
arrow_reader
arrow_writer_layout
arrow_reader
arrow_statistics
arrow_writer
compression
encoding
metadata
row_selector";
  version = "53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
0.22
7.0
1.1
>= 0.4.34, < 0.4.40
4.1
1.4.2
1.0
0.3
2.1
0.15
0.11
0.4
0.4
0.11.0
1.0
0.3
1.0
1.0
1.0
0.32.0
0.17
1.0
1.6
0.13
53.4.1
0.22
7.0
0.5
1.0
0.11
0.11.0
0.8
1.0
1.0
3.0
1.0
0.13
0.8
0.8
>=2.0.0, <2.0.14
>=2.0.0, <2.0.14";
  src = ././vendor/parquet-53.4.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "parquet
parquet
parquet-concat
parquet-fromcsv
parquet-index
parquet-layout
parquet-read
parquet-rewrite
parquet-rowcount
parquet-schema
parquet-show-bloom-filter
async_read_parquet
external_metadata
read_parquet
read_with_rowgroup
write_parquet
arrow_reader
arrow_writer_layout
arrow_reader
arrow_statistics
arrow_writer
compression
encoding
metadata
row_selector";
  #   license = lib.licenses.mit;
  # };
}
