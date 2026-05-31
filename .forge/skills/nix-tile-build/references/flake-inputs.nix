# Reference flake input structure for nix-tile-build
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  flake-utils.url = "github:numtide/flake-utils";

  # Bare mirror inputs (for combinedSrc)
  erdfa-publish-src = {
    url = "git+file:///mnt/data1/git/solana.solfunmeme.com/erdfa-publish.git";
    flake = false;
  };
  rust-ipfs-src = {
    url = "git+file:///home/mdupont/git/github.com/meta-introspector/rust-ipfs.git";
    flake = false;
  };

  # Tile inputs
  org-tile-src = {
    url = "git+file:///mnt/data1/kant/pastebin?dir=tiles/org-tile";
  };
  zos-circuit-tile-src = {
    url = "git+file:///mnt/data1/kant/pastebin?dir=tiles/zos-circuit-tile";
  };
};
