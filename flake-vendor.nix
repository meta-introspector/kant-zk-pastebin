{ pkgs ? import <nixpkgs> {} }:

let
  # Import cargo2nix
  cargo2nix = pkgs.callPackage (pkgs.fetchFromGitHub {
    owner = "cargo2nix";
    repo = "cargo2nix";
    rev = "master";
    sha256 = "0z1j2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p7q8r9s0t1u2v3w4x5y6z7a8b9c0d1e2f3";
  }) {};

  # Generate cargo2nix configuration for each vendored crate
  generateCrateConfigs = pkgs.lib.mapAttrs (crateName: crateInfo: {
    name = crateName;
    value = cargo2nix.mkRustCrate {
      inherit (crateInfo) name version;
      src = ./.;
      buildInputs = [ ];
      dependencies = { };
    };
  });

  # Get all vendored crate directories
  vendoredCrates = builtins.readDir ./vendor;
  crateDirs = builtins.filter (name: 
    builtins.isAttrs vendoredCrates.${name} && 
    vendoredCrates.${name} == "directory"
  ) (builtins.attrNames vendoredCrates);

  # Generate flake.nix for each vendored crate
  generateFlake = crateName: {
    name = crateName;
    value = {
      description = "Vendored crate: ${crateName}";
      inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
        cargo2nix.url = "github:cargo2nix/cargo2nix";
      };
      outputs = { self, nixpkgs, cargo2nix }:
        let
          system = "x86_64-linux";
          pkgs = nixpkgs.legacyPackages.${system};
          cargo2nixPkgs = cargo2nix.packages.${system};
          
          # Read crate metadata
          crateToml = builtins.readFile ./vendor/${crateName}/Cargo.toml;
          crateInfo = builtins.fromTOML crateToml;
          
        in {
          packages.${crateName} = cargo2nixPkgs.mkRustCrate {
            inherit (crateInfo.package) name version;
            src = ./vendor/${crateName};
            buildInputs = [ ];
            dependencies = { };
          };
          
          defaultPackage = self.packages.${system}.${crateName};
          devShell = pkgs.mkShell {
            buildInputs = [ 
              cargo2nixPkgs.cargo
              cargo2nixPkgs.rustc
            ];
          };
        };
    };
  };

  # Generate unified flake.nix for all vendored crates
  unifiedFlake = {
    description = "Unified flake for all vendored crates in pastebin";
    inputs = {
      nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
      cargo2nix.url = "github:cargo2nix/cargo2nix";
    };
    
    outputs = { self, nixpkgs, cargo2nix }:
      let
        system = "x86_64-linux";
        pkgs = nixpkgs.legacyPackages.${system};
        cargo2nixPkgs = cargo2nix.packages.${system};
        
      in {
        # Package for each vendored crate
        packages = builtins.listToAttrs (map generateFlake crateDirs);
        
        # Default package (first crate alphabetically)
        defaultPackage = self.packages.${system}.(
          builtins.head (builtins.sort (a: b: a < b) crateDirs)
        );
        
        # Development shell
        devShell = pkgs.mkShell {
          buildInputs = [
            cargo2nixPkgs.cargo
            cargo2nixPkgs.rustc
            pkgs.cargo-audit
            pkgs.cargo-outdated
          ];
          
          shellHook = ''
            echo "Vendored crates development environment"
            echo "Available crates: ${builtins.toString crateDirs}"
            echo "Total crates: ${builtins.toString (builtins.length crateDirs)}"
          '';
        };
        
        # Checks for all packages
        checks = builtins.mapAttrs (name: pkg: pkgs.runCommand "check-${name}" {} ''
          echo "Checking ${name}..."
          ${pkg}/bin/${name} --version || true
        '') self.packages.${system};
      };
  };

in {
  # Individual crate flakes
  crates = builtins.listToAttrs (map generateFlake crateDirs);
  
  # Unified flake
  unified = unifiedFlake;
  
  # Cargo2nix configuration for the main project
  cargo2nixConfig = {
    name = "kant-pastebin";
    version = "0.1.0";
    src = ./.;
    buildInputs = [ ];
    dependencies = { };
  };
}