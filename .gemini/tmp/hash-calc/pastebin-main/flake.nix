{
  description = "Temp flake to calculate hash for pastebin-main";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  outputs = { self, nixpkgs }: {
    defaultPackage.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.stdenv.mkDerivation {
      name = "dummy-pastebin-main";
      src = builtins.fetchGit {
        url = "/mnt/data1/git/github.com/meta-introspector/kant-zk-pastebin";
        rev = "e15649f270ffda97d4dfa7e6f4953fe2999a1637";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      installPhase = "touch $out/dummy";
    };
  };
}