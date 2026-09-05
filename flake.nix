{
  description = "Kant ZK Pastebin — Nix shell for Cloudflare Pages + Worker deploys";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        nodejs = pkgs.nodejs_22;
        wrangler = pkgs.writeShellApplication {
          name = "wrangler";
          runtimeInputs = [ nodejs ];
          text = ''
            exec ${nodejs}/bin/node ${nodejs}/lib/node_modules/wrangler/wrangler.js "$@"
          '';
        };
      in {
        devShells.default = pkgs.mkShell {
          packages = [ nodejs ];
        };

        packages = {
          inherit nodejs;
          wrangler = wrangler;
          default = wrangler;
        };
      }
    );
}
