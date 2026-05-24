{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "icu_normalizer
icu_normalizer
tests
bench
canonical_composition
canonical_decomposition
composing_normalizer_nfc
composing_normalizer_nfkc
decomposing_normalizer_nfd
decomposing_normalizer_nfkd
utf16_throughput";
  version = "2.2.0
0.2.0
0.6.0
~2.2.0
~2.2.0
~2.2.0
2.2.0
1.0.220
1.10.0
1.0.2
1.0.2
1.0.0
0.11.6
0.3.0
0.7.2
2.0.0
1.0.0
1.0.0
0.5.0";
  src = ././vendor/icu_normalizer-2.2.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "icu_normalizer
icu_normalizer
tests
bench
canonical_composition
canonical_decomposition
composing_normalizer_nfc
composing_normalizer_nfkc
decomposing_normalizer_nfd
decomposing_normalizer_nfkd
utf16_throughput";
  #   license = lib.licenses.mit;
  # };
}
