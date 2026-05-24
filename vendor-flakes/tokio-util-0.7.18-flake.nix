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
  description = "Vendored crate: tokio-util
tokio_util
_require_full
abort_on_drop
codecs
compat
context
framed
framed_read
framed_stream
framed_write
future
io_inspect
io_reader_stream
io_simplex
io_sink_writer
io_stream_reader
io_sync_bridge
length_delimited
mpsc
panic
poll_semaphore
reusable_box
spawn_pinned
sync_cancellation_token
task_join_map
task_join_queue
task_tracker
time_delay_queue
udp (0.7.18
1.5.0
0.3.0
0.3.0
0.3.0
0.3.0
0.15.0
0.2.11
0.4.4
1.44.0
0.1.29
0.3.0
0.3.0
0.3.5
0.12.0
3.1.0
1.0.0
0.1
0.4.0
0.7)";
  
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
      packages.${system}.tokio-util-0.7.18 = cargo2nixPkgs.mkRustCrate {
        name = "tokio-util
tokio_util
_require_full
abort_on_drop
codecs
compat
context
framed
framed_read
framed_stream
framed_write
future
io_inspect
io_reader_stream
io_simplex
io_sink_writer
io_stream_reader
io_sync_bridge
length_delimited
mpsc
panic
poll_semaphore
reusable_box
spawn_pinned
sync_cancellation_token
task_join_map
task_join_queue
task_tracker
time_delay_queue
udp";
        version = "0.7.18
1.5.0
0.3.0
0.3.0
0.3.0
0.3.0
0.15.0
0.2.11
0.4.4
1.44.0
0.1.29
0.3.0
0.3.0
0.3.5
0.12.0
3.1.0
1.0.0
0.1
0.4.0
0.7";
        src = ././vendor/tokio-util-0.7.18;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.tokio-util-0.7.18;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
