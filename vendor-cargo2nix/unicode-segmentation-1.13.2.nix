{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "unicode-segmentation
unicode_segmentation
test
chars
unicode_word_indices
word_bounds
words";
  version = "1.13.2
0.5
1.7.0
1.0";
  src = ././vendor/unicode-segmentation-1.13.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "unicode-segmentation
unicode_segmentation
test
chars
unicode_word_indices
word_bounds
words";
  #   license = lib.licenses.mit;
  # };
}
