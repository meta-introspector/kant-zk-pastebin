{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
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
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "tokio-util
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
  #   license = lib.licenses.mit;
  # };
}
