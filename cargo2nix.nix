{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "kant-pastebin";
  version = "0.1.0";
  src = ./.;
  
  buildInputs = [ ];
  
  dependencies = {
    # Add your dependencies here with proper versions
    # serde = "1.0";
    # tokio = "1.0";
  };
  
  # Add crate-specific configuration
  meta = {
    description = "Kant Pastebin - UUCP + zkTLS + IPFS pastebin service";
    license = lib.licenses.mit;
    maintainers = [ "mdupont" ];
  };
}
