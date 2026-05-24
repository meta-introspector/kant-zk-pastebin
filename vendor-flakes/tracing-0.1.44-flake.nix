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
  description = "Vendored crate: tracing
tracing
enabled
event
filter_caching_is_lexically_scoped
filters_are_not_reevaluated_for_the_same_span
filters_are_reevaluated_for_different_call_sites
filters_dont_leak
future_send
instrument
macro_imports
macros
macros_incompatible_concat
max_level_hint
missed_register_callsite
multiple_max_level_hints
no_subscriber
register_callsite_deadlock
scoped_clobbers_default
span
subscriber
baseline
dispatch_get_clone
dispatch_get_ref
empty_span
enter_span
event
shared
span_fields
span_no_fields
span_repeated (0.1.44
0.4.17
0.2.9
0.1.31
0.1.36
0.3.6
0.3.21
0.4.17
0.3.38)";
  
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
      packages.${system}.tracing-0.1.44 = cargo2nixPkgs.mkRustCrate {
        name = "tracing
tracing
enabled
event
filter_caching_is_lexically_scoped
filters_are_not_reevaluated_for_the_same_span
filters_are_reevaluated_for_different_call_sites
filters_dont_leak
future_send
instrument
macro_imports
macros
macros_incompatible_concat
max_level_hint
missed_register_callsite
multiple_max_level_hints
no_subscriber
register_callsite_deadlock
scoped_clobbers_default
span
subscriber
baseline
dispatch_get_clone
dispatch_get_ref
empty_span
enter_span
event
shared
span_fields
span_no_fields
span_repeated";
        version = "0.1.44
0.4.17
0.2.9
0.1.31
0.1.36
0.3.6
0.3.21
0.4.17
0.3.38";
        src = ././vendor/tracing-0.1.44;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.tracing-0.1.44;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
