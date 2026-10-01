{ config, lib, pkgs, ... }:

let
  domain = "solana.solfunmeme.com";
in
{
  services.nginx.virtualHosts."solana.solfunmeme.com" = {
    serverName = domain;
    forceSSL = true;
    sslCertificate = "/etc/letsencrypt/live/solana.solfunmeme.com/fullchain.pem";
    sslCertificateKey = "/etc/letsencrypt/live/solana.solfunmeme.com/privkey.pem";

    locations."/pastebin/" = {
      proxyPass = "http://127.0.0.1:8090/";
      proxyWebsockets = true;
    };

    locations."/tile/ebpf/" = {
      proxyPass = "http://127.0.0.1:18090/ebpf/";
    };

    locations."/tile/search/" = {
      proxyPass = "http://127.0.0.1:18090/search/";
    };

    locations."/dashboard/ebpf" = {
      proxyPass = "http://127.0.0.1:18090/dashboard/ebpf";
    };

    locations."/dashboard/search" = {
      proxyPass = "http://127.0.0.1:18090/dashboard/search";
    };
  };
}