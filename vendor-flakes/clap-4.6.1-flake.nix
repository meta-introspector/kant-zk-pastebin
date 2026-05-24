{ pkgs ? import <nixpkgs> {} }:

let
  cargo2nix = pkgs.callPackage (pkgs.fetchFromGitHub {
    owner = "cargo2nix";
    repo = "cargo2nix";
    rev = "master";
    sha256 = "0z1j2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p7q8r9s0t1u2v3w4x5y6z7a8b9c0d1e2f3";
  }) {};
in
{
  description = "Vendored crate: clap
clap
stdio-fixture
01_quick
01_quick_derive
02_app_settings
02_app_settings_derive
02_apps
02_apps_derive
02_crate
02_crate_derive
03_01_flag_bool
03_01_flag_bool_derive
03_01_flag_count
03_01_flag_count_derive
03_02_option
03_02_option_derive
03_02_option_mult
03_02_option_mult_derive
03_03_positional
03_03_positional_derive
03_03_positional_mult
03_03_positional_mult_derive
03_04_subcommands
03_04_subcommands_alt_derive
03_04_subcommands_derive
03_05_default_values
03_05_default_values_derive
03_06_optional_derive
03_06_required
04_01_enum
04_01_enum_derive
04_01_possible
04_02_parse
04_02_parse_derive
04_02_validate
04_02_validate_derive
04_03_relations
04_03_relations_derive
04_04_custom
04_04_custom_derive
05_01_assert
05_01_assert_derive
busybox
cargo-example
cargo-example-derive
demo
escaped-positional
escaped-positional-derive
find
git
git-derive
hostname
interop_augment_args
interop_augment_subcommands
interop_flatten_hand_args
interop_hand_subcommand
pacman
repl
repl-derive
typed-derive (4.6.1
=4.6.0
=4.6.1
1.0.16
0.15.2
0.2.23
1.0.22
1.0.27
1.3.0
1.2.0
1.0.116
1.2.0)";
  
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
      packages.${system}.clap-4.6.1 = cargo2nixPkgs.mkRustCrate {
        name = "clap
clap
stdio-fixture
01_quick
01_quick_derive
02_app_settings
02_app_settings_derive
02_apps
02_apps_derive
02_crate
02_crate_derive
03_01_flag_bool
03_01_flag_bool_derive
03_01_flag_count
03_01_flag_count_derive
03_02_option
03_02_option_derive
03_02_option_mult
03_02_option_mult_derive
03_03_positional
03_03_positional_derive
03_03_positional_mult
03_03_positional_mult_derive
03_04_subcommands
03_04_subcommands_alt_derive
03_04_subcommands_derive
03_05_default_values
03_05_default_values_derive
03_06_optional_derive
03_06_required
04_01_enum
04_01_enum_derive
04_01_possible
04_02_parse
04_02_parse_derive
04_02_validate
04_02_validate_derive
04_03_relations
04_03_relations_derive
04_04_custom
04_04_custom_derive
05_01_assert
05_01_assert_derive
busybox
cargo-example
cargo-example-derive
demo
escaped-positional
escaped-positional-derive
find
git
git-derive
hostname
interop_augment_args
interop_augment_subcommands
interop_flatten_hand_args
interop_hand_subcommand
pacman
repl
repl-derive
typed-derive";
        version = "4.6.1
=4.6.0
=4.6.1
1.0.16
0.15.2
0.2.23
1.0.22
1.0.27
1.3.0
1.2.0
1.0.116
1.2.0";
        src = ././vendor/clap-4.6.1;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.clap-4.6.1;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
