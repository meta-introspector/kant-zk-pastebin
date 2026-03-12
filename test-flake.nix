{
  description = "Kant Pastebin Tests";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      
      nodeEnv = pkgs.mkShell {
        buildInputs = with pkgs; [
          nodejs
          nodePackages.npm
          chromium
        ];
        
        shellHook = ''
          export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1
          export PUPPETEER_EXECUTABLE_PATH=${pkgs.chromium}/bin/chromium
        '';
      };
    in
    {
      devShells.${system}.default = nodeEnv;
      
      packages.${system}.test = pkgs.writeShellScriptBin "test-pastebin" ''
        export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1
        export PUPPETEER_EXECUTABLE_PATH=${pkgs.chromium}/bin/chromium
        export TEST_PORT=9191
        
        cd ${./.}
        ${pkgs.nodejs}/bin/node test-pastebin.js
      '';
    };
}
