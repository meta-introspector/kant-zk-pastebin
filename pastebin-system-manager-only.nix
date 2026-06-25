{ config, pkgs, self, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  kant-pastebin = self.packages.${system}.kant-pastebin;
  domain = "solana.solfunmeme.com";
in {
  config = {
    systemd.tmpfiles.rules = [
      "d /mnt/data1/spool/uucp/pastebin 0755 kant kant -"
    ];

    systemd.services.kant-pastebin = {
      enable = true;
      description = "Kant Pastebin - UUCP + zkTLS + IPFS";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple";
        User = "kant";
        Group = "kant";
        ExecStart = "${kant-pastebin}/bin/kant-pastebin";
        Restart = "always";
        RestartSec = "10";
        WorkingDirectory = "/mnt/data1/kant/pastebin";
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
        UUCP_SPOOL = "/mnt/data1/spool/uucp/pastebin";
        BASE_PATH = "/pastebin";
        BASE_URL = "https://${domain}";
        NFT_DIR = "/mnt/data1/time-2026/03-march/13/nft_enriched";
        ENRICH_PIPELINE = "/mnt/data1/time-2026/03-march/09/mmgroup-rust/enrich-qid.sh";
        RUST_LOG = "info";
        TILES_DIR = "";
      };
    };
  };
}
