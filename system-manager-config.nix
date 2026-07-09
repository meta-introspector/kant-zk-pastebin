# Deprecated — use ~/projects/system-manager/all-services.nix instead.
#
# This file previously contained a larger system-manager config with
# references to removed inputs (zos-circuit-tile, org-tile, nora-tile,
# dasl-tiles-rust, index-docs, pipelight). It is kept for reference only.
#
# Active config: ~/projects/system-manager/all-services.nix

{ config, lib, pkgs, self, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  kant-pastebin = self.packages.${system}.kant-pastebin;
in {
  config = {
    systemd.services.kant-pastebin = {
      enable = true;
      description = "Kant Pastebin - UUCP + zkTLS + IPFS";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple";
        User = "kant";
        Group = "kant";
        WorkingDirectory = "/mnt/data1/kant/pastebin";
        ExecStart = "${kant-pastebin}/bin/kant-pastebin";
        Restart = "always";
        RestartSec = "10";
        TimeoutStartSec = 0;
        TimeoutStopSec = 0;
        TimeoutAbortSec = 0;
        TimeoutSec = 0;
      };
      environment = {
        BIND_ADDR = "127.0.0.1:8090";
        BASE_PATH = "/pastebin";
        BASE_URL = "https://solana.solfunmeme.com";
        RUST_LOG = "info";
      };
    };
  };
}
