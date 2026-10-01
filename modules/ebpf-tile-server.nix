{ config, lib, pkgs, dasl-tiles-rust, ... }:
{
  systemd.services.dasl-tile-server = {
    enable = true;
    description = "DASL Tile Server — eBPF + search endpoints";
    after = [ "network.target" ];
    wantedBy = [ "system-manager.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${dasl-tiles-rust.packages.x86_64-linux.default}/bin/tile-server -d solana.solfunmeme.com -p 18090";
      Restart = "always";
      RestartSec = "10";
      WorkingDirectory = "/home/mdupont/dasl-tiles-rust";
      Environment = "DASL_TESTING_ROOT=/mnt/data1/time-2026/02-february/22/dasl/dasl-testing";
      TimeoutStartSec = 0;
      TimeoutStopSec = 0;
    };
  };
}