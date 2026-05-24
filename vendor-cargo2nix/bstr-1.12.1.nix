{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "bstr
bstr
graphemes
graphemes-std
lines
lines-std
uppercase
uppercase-std
words
words-std";
  version = "1.12.1
2.7.1
0.4.1
1.0.85
1
0.1.3
1.2.1";
  src = ././vendor/bstr-1.12.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "bstr
bstr
graphemes
graphemes-std
lines
lines-std
uppercase
uppercase-std
words
words-std";
  #   license = lib.licenses.mit;
  # };
}
