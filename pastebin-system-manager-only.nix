{ config, pkgs, self, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  kant-pastebin = self.packages.${system}.kant-pastebin;
  domain = "solana.solfunmeme.com";

  leDir = "/etc/letsencrypt/live/${domain}";
  leCert = "${leDir}/fullchain.pem";
  leKey  = "${leDir}/privkey.pem";
  selfSignedDir = "/mnt/data1/kant/pastebin/ssl";
  selfSignedCert = "${selfSignedDir}/${domain}.crt";
  selfSignedKey  = "${selfSignedDir}/${domain}.key";
  activeCert = if builtins.pathExists leCert then leCert else selfSignedCert;
  activeKey  = if builtins.pathExists leKey  then leKey  else selfSignedKey;
in {
  config = {
    systemd.tmpfiles.rules = [
      "d /var/spool/uucp/pastebin 0755 kant kant -"
    ];

    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      commonHttpConfig = ''
        access_log off;
      '';

      virtualHosts."${domain}" = {
        forceSSL = true;
        sslCertificate = activeCert;
        sslCertificateKey = activeKey;

        locations."/pastebin/" = {
          proxyPass = "http://127.0.0.1:8090/";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            client_max_body_size 0;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
            proxy_connect_timeout 3600s;
            proxy_buffering off;
            proxy_request_buffering off;
          '';
        };
      };
    };

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
        UUCP_SPOOL = "/var/spool/uucp/pastebin";
        BASE_PATH = "/pastebin";
        BASE_URL = "https://${domain}";
        NFT_DIR = "/mnt/data1/time-2026/03-march/13/nft_enriched";
        ENRICH_PIPELINE = "/mnt/data1/time-2026/03-march/09/mmgroup-rust/enrich-qid.sh";
        RUST_LOG = "info";
        TILES_DIR = "";
      };
    };

    systemd.services.ssl-selfsigned = {
      enable = true;
      description = "Generate self-signed SSL fallback certificate for ${domain}";
      before = [ "nginx.service" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = let
          script = pkgs.writeShellScript "ssl-selfsigned" ''
            set -eu
            if [ -f "${leCert}" ] && [ -f "${leKey}" ]; then
              echo "LE certs present at ${leDir} — skipping self-signed"
              exit 0
            fi

            leArchive="/etc/letsencrypt/archive/${domain}"
            ${pkgs.coreutils}/bin/mkdir -p "''${leArchive}" "${selfSignedDir}" "${leDir}"
            ${pkgs.coreutils}/bin/chmod 755 "${selfSignedDir}" "''${leArchive}" "${leDir}" 2>/dev/null || true

            if [ ! -f "${selfSignedCert}" ] || [ ! -f "${selfSignedKey}" ]; then
              echo "Generating self-signed cert for ${domain}"
              ${pkgs.openssl}/bin/openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "${selfSignedKey}.tmp" -out "${selfSignedCert}.tmp" \
                -subj /CN=${domain} 2>/dev/null
              ${pkgs.coreutils}/bin/mv "${selfSignedKey}.tmp" "${selfSignedKey}"
              ${pkgs.coreutils}/bin/mv "${selfSignedCert}.tmp" "${selfSignedCert}"
              ${pkgs.coreutils}/bin/chmod 644 "${selfSignedCert}"
              ${pkgs.coreutils}/bin/chmod 644 "${selfSignedKey}"
            fi

            for f in cert.pem chain.pem fullchain.pem; do
              [ -L "${leDir}/$f" ] && continue
              ${pkgs.coreutils}/bin/ln -s "${selfSignedCert}" "${leDir}/$f" 2>/dev/null || true
            done
            [ -L "${leDir}/privkey.pem" ] || \
              ${pkgs.coreutils}/bin/ln -s "${selfSignedKey}" "${leDir}/privkey.pem" 2>/dev/null || true

            ${pkgs.coreutils}/bin/chmod 755 /etc/letsencrypt/archive /etc/letsencrypt/archive/${domain} 2>/dev/null || true
            ${pkgs.coreutils}/bin/chmod 644 /etc/letsencrypt/archive/${domain}/*.pem 2>/dev/null || true
          '';
        in "${script}";
      };
    };

    systemd.services.certbot-renew = {
      enable = true;
      description = "Renew Let's Encrypt SSL certificate for ${domain} via Namecheap DNS-01";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = "/etc/certbot/namecheap.env";
        ExecStart = "${pkgs.certbot}/bin/certbot renew --non-interactive";
        ExecStartPost = let
          fixPerms = pkgs.writeShellScript "certbot-fix-perms" ''
            set -eu
            chmod 755 /etc/letsencrypt/archive /etc/letsencrypt/archive/${domain} 2>/dev/null || true
            chmod 644 /etc/letsencrypt/archive/${domain}/*.pem 2>/dev/null || true
            touch /var/log/nginx/access.log /var/log/nginx/error.log 2>/dev/null || true
            chown nginx:nginx /var/log/nginx/access.log /var/log/nginx/error.log 2>/dev/null || true
            systemctl reload-or-restart nginx.service 2>/dev/null || true
          '';
        in "${fixPerms}";
      };
    };

    systemd.timers.certbot-renew = {
      enable = true;
      description = "Daily certbot renewal check for ${domain}";
      wants = [ "certbot-renew.service" ];
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "3600";
      };
    };

    environment.systemPackages = with pkgs; [
      curl
      jq
      nginx
      openssl
      certbot
    ];
  };
}
