{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "wasip2
wasip2
cli-command
cli-command-no_std
hello-world
hello-world-no_std
http-proxy
http-proxy-no_std";
  version = "1.0.2+wasi-0.2.9
1.0
1.0
0.51.0";
  src = ././vendor/wasip2-1.0.2+wasi-0.2.9;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "wasip2
wasip2
cli-command
cli-command-no_std
hello-world
hello-world-no_std
http-proxy
http-proxy-no_std";
  #   license = lib.licenses.mit;
  # };
}
