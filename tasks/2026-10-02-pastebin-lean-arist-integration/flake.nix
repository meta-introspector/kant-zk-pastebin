{
  description = "2026-10-02-pastebin-lean-arist-integration — see SYSTEM.md";
  inputs = {
    nixpkgs.url = "git+file:///mnt/data1/git/github.com/NixOS/nixpkgs.git";
    flake-utils.url = "git+file:///mnt/data1/git/github.com/numtide/flake-utils.git";
  };
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system}; in {
        devShells.default = pkgs.mkShell {
          name = "2026-10-02-pastebin-lean-arist-integration";
          buildInputs = [
            pkgs.nodejs_22
            pkgs.git
          ];
          shellHook = ''
            echo "Task ready: 2026-10-02-pastebin-lean-arist-integration — read SYSTEM.md first"
          '';
        };
      });
}
