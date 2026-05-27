{ config, lib, pkgs, self, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  kant-pastebin = self.packages.${system}.kant-pastebin;
  index-docs = self.packages.${system}.index-docs;

in
{
  config = {
    services.nginx.enable = true;

    services.nginx.virtualHosts."solana.solfunmeme.com" = {
      serverName = "solana.solfunmeme.com";
      locations."/pastebin/" = {
        proxyPass = "http://127.0.0.1:8090/";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };
    };

    systemd.services.kant-pastebin = {
      enable = true;
      description = "Kant Pastebin - UUCP + zkTLS + IPFS";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${kant-pastebin}/bin/kant-pastebin";
        Restart = "always";
        RestartSec = "10";
        WorkingDirectory = "/mnt/data1/kant/pastebin";
      };
      environment = {
        BIND_ADDR = "127.0.0.1:8090";
        UUCP_SPOOL = "/mnt/data1/spool/uucp/pastebin";
        BASE_PATH = "/pastebin";
        BASE_URL = "https://solana.solfunmeme.com";
        NFT_DIR = "/mnt/data1/time-2026/03-march/13/nft_enriched";
        ENRICH_PIPELINE = "/mnt/data1/time-2026/03-march/09/mmgroup-rust/enrich-qid.sh";
        RUST_LOG = "info";
      };
    };

    systemd.services.kant-index-docs = {
      enable = true;
      description = "Index DOCS and spool to Kant Pastebin";
      after = [ "kant-pastebin.service" ];
      requires = [ "kant-pastebin.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${index-docs}/bin/kant-index-docs";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    systemd.timers.kant-index-docs = {
      enable = true;
      description = "Index DOCS and spool daily";
      wants = [ "kant-index-docs.service" ];
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    environment.systemPackages = with pkgs; [
      curl
      jq
      kubo
      nginx
    ];
  };
}
