{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "futures-channel
futures_channel
channel
mpsc
mpsc-close
mpsc-size_hint
oneshot
sync_mpsc";
  version = "0.3.32
0.3.32
0.3.32";
  src = ././vendor/futures-channel-0.3.32;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "futures-channel
futures_channel
channel
mpsc
mpsc-close
mpsc-size_hint
oneshot
sync_mpsc";
  #   license = lib.licenses.mit;
  # };
}
