{ config, lib, pkgs, pastebin-src, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  kant-pastebin = pastebin-src.packages.${system}.kant-pastebin;
in
{
  config = {
    users.groups.kant.gid = 30036;
    users.users.kant = {
      uid = 942;
      isSystemUser = true;
      group = "kant";
      home = "/mnt/data1/kant";
      createHome = true;
      extraGroups = [ "mdupont" ];
      shell = "${pkgs.bash}/bin/bash";
    };

    systemd.services.kant-pastebin = {
      enable = true;
      description = "Kant Pastebin - UUCP + zkTLS + IPFS";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "kant";
        Group = "kant";
        SupplementaryGroups = [ "mdupont" ];
        WorkingDirectory = "/mnt/data1/kant/pastebin";
        ExecStart = "${kant-pastebin}/bin/kant-pastebin";
        Restart = "always";
        RestartSec = "10";
        TimeoutStartSec = 0;
        TimeoutStopSec = 0;
        TimeoutAbortSec = 0;
        TimeoutSec = 0;
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
      };
      environment = {
        BIND_ADDR = "127.0.0.1:8090";
        UUCP_SPOOL = "/var/spool/uucp/pastebin";
        BASE_PATH = "/pastebin";
        BASE_URL = "https://solana.solfunmeme.com";
        NFT_DIR = "/mnt/data1/time-2026/03-march/13/nft_enriched";
        ENRICH_PIPELINE = "/mnt/data1/time-2026/03-march/09/mmgroup-rust/enrich-qid.sh";
        RUST_LOG = "info";
        TILES_DIR = "";
      };
    };
  };
}
