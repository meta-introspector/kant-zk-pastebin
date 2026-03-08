{
  description = "Kant Pastebin - UUCP + zkTLS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        kubo = pkgs.kubo;
      in
      {
        packages = {
          kant-pastebin = pkgs.rustPlatform.buildRustPackage {
            pname = "kant-pastebin";
            version = "0.1.0";
            src = ./.;
            cargoLock.lockFile = ./Cargo.lock;
            nativeBuildInputs = [ pkgs.pkg-config ];
            buildInputs = [ pkgs.openssl ];
          };

          default = self.packages.${system}.kant-pastebin;
          
          systemd-service = pkgs.writeTextFile {
            name = "kant-pastebin.service";
            text = ''
              [Unit]
              Description=Kant Pastebin - UUCP + zkTLS + IPFS
              After=network.target

              [Service]
              Type=simple
              WorkingDirectory=/mnt/data1/kant/pastebin
              ExecStart=${self.packages.${system}.kant-pastebin}/bin/kant-pastebin
              Restart=always
              RestartSec=10
              Environment="BIND_ADDR=127.0.0.1:8090"
              Environment="UUCP_SPOOL=/mnt/data1/spool/uucp/pastebin"
              Environment="RUST_LOG=info"
              Environment="PATH=${kubo}/bin"

              [Install]
              WantedBy=default.target
            '';
          };
        };

        apps = {
          kant-pastebin = {
            type = "app";
            program = "${self.packages.${system}.kant-pastebin}/bin/kant-pastebin";
          };
          default = self.apps.${system}.kant-pastebin;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            cargo
            rustc
            rust-analyzer
            rustfmt
            clippy
            pkg-config
            openssl
          ];
        };
      }
    );
}
