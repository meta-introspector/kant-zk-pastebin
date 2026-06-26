{ config, pkgs, self, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  kant-pastebin = self.packages.${system}.kant-pastebin;
  domain = "solana.solfunmeme.com";

  # SSL certs — always use the live directory. The ssl-selfsigned service
  # ensures symlinks exist there (pointing to LE certs or self-signed fallback).
  # Do NOT use builtins.pathExists here — that bakes a build-time check into
  # an immutable store path. The runtime ssl-selfsigned service handles fallback.
  sslCert = "/etc/letsencrypt/live/${domain}/fullchain.pem";
  sslKey  = "/etc/letsencrypt/live/${domain}/privkey.pem";
in {
  config = {
    systemd.tmpfiles.rules = [
      "d /var/spool/uucp/pastebin 0755 kant kant -"
    ];

    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      commonHttpConfig = ''
        # Private server — no upload limits on any endpoint
        # (client_max_body_size is set per-location for /pastebin/)
        # Larger buffer so $request_body captures body content in error logs
        client_body_buffer_size 1024k;

        # Map non-2xx status codes to flag for error document logging
        map $status $is_error {
          ~^[23]  0;
          default 1;
        }

        # Research-grade access logging (all requests)
        log_format research '"$time_iso8601" client=$remote_addr method=$request_method uri=$request_uri status=$status body_bytes=$body_bytes_sent referer=$http_referer user_agent=$http_user_agent request_time=''${request_time}s upstream_addr=$upstream_addr upstream_status=$upstream_status scheme=$scheme host=$host';

        access_log /var/log/nginx/research.access.log research;
        error_log /var/log/nginx/research.error.log warn;

        # Structured error document archive (all 4xx/5xx responses)
        log_format error_doc '
=== Error Document ===
Date: $time_iso8601
Client: $remote_addr
Method: $request_method
URI: $request_uri
Status: $status
Bytes: $body_bytes_sent
Content-Type: $sent_http_content_type
Referer: $http_referer
User-Agent: $http_user_agent
Request-Time: $request_time
Upstream-Addr: $upstream_addr
Upstream-Status: $upstream_status
Host: $host
X-Forwarded-For: $http_x_forwarded_for
Server-Name: $server_name
Request-Body: $request_body
-------------------
';
        access_log /var/log/nginx/error-docs/error.log error_doc if=$is_error;
      '';

      virtualHosts."${domain}" = {
        forceSSL = true;
        sslCertificate = sslCert;
        sslCertificateKey = sslKey;

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

        # Serve error documents for research
        locations."/nginx-docs/errors/" = {
          alias = "/var/log/nginx/error-docs/";
          extraConfig = ''
            autoindex on;
            autoindex_exact_size off;
            autoindex_localtime on;
            default_type text/markdown;
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

    systemd.services.nginx-log-setup = {
      enable = true;
      description = "Create nginx research log files and error-docs directory";
      before = [ "nginx.service" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = let
          script = pkgs.writeShellScript "nginx-log-setup" ''
            set -eu
            # Use the private log path that matches systemd's resolved view
            log_base="/var/log/nginx"
            # Resolve through private symlink
            if [ -L /var/log ]; then
              real_log="$(readlink -f /var/log)"
              if [ -n "$real_log" ] && [ "$real_log" != /var/log ]; then
                log_base="$real_log/nginx"
              fi
            fi
            ${pkgs.coreutils}/bin/mkdir -p "$log_base/error-docs"
            touch "$log_base/research.access.log" "$log_base/research.error.log"
            chmod 755 "$log_base" "$log_base/error-docs"
            chmod 644 "$log_base/research.access.log" "$log_base/research.error.log"
            # Symlink from /var/log/nginx if it doesn't exist
            if [ ! -d /var/log/nginx ]; then
              ln -sf "$log_base" /var/log/nginx 2>/dev/null || true
            fi
          '';
        in "${script}";
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
            domain="${domain}"
            leArchive="/etc/letsencrypt/archive/$domain"
            leDir="/etc/letsencrypt/live/$domain"
            selfSignedDir="/mnt/data1/kant/pastebin/ssl"
            selfSignedCert="$selfSignedDir/$domain.crt"
            selfSignedKey="$selfSignedDir/$domain.key"

            # Create all needed directories
            ${pkgs.coreutils}/bin/mkdir -p "$leArchive" "$selfSignedDir" "$leDir"
            ${pkgs.coreutils}/bin/chmod 755 "$selfSignedDir" "$leArchive" "$leDir" 2>/dev/null || true

            # Generate self-signed cert once
            if [ ! -f "$selfSignedCert" ] || [ ! -f "$selfSignedKey" ]; then
              echo "[ssl-selfsigned] Generating self-signed cert for $domain"
              ${pkgs.openssl}/bin/openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "$selfSignedKey.tmp" -out "$selfSignedCert.tmp" \
                -subj /CN=$domain 2>/dev/null
              ${pkgs.coreutils}/bin/mv "$selfSignedKey.tmp" "$selfSignedKey"
              ${pkgs.coreutils}/bin/mv "$selfSignedCert.tmp" "$selfSignedCert"
              ${pkgs.coreutils}/bin/chmod 644 "$selfSignedCert"
              ${pkgs.coreutils}/bin/chmod 644 "$selfSignedKey"
            fi

            # Check for LE certs — use the latest in the archive
            latest_fullchain="$(ls "$leArchive"/fullchain*.pem 2>/dev/null | sort | tail -1)"
            latest_privkey="$(ls "$leArchive"/privkey*.pem 2>/dev/null | sort | tail -1)"

            if [ -n "$latest_fullchain" ] && [ -n "$latest_privkey" ]; then
              echo "[ssl-selfsigned] LE certs found — symlinking latest into live dir"
              # Find the corresponding cert and chain
              latest_cert="$(ls "$leArchive"/cert*.pem 2>/dev/null | sort | tail -1)"
              latest_chain="$(ls "$leArchive"/chain*.pem 2>/dev/null | sort | tail -1)"
              ln -sf "$latest_cert"      "$leDir/cert.pem"
              ln -sf "$latest_chain"     "$leDir/chain.pem"
              ln -sf "$latest_fullchain" "$leDir/fullchain.pem"
              ln -sf "$latest_privkey"   "$leDir/privkey.pem"
            else
              echo "[ssl-selfsigned] No LE certs — using self-signed fallback"
              ln -sf "$selfSignedCert" "$leDir/fullchain.pem"
              ln -sf "$selfSignedCert" "$leDir/cert.pem"
              ln -sf "$selfSignedCert" "$leDir/chain.pem"
              ln -sf "$selfSignedKey"  "$leDir/privkey.pem"
            fi

            # Permissions for LE archive
            ${pkgs.coreutils}/bin/chmod 755 /etc/letsencrypt/archive /etc/letsencrypt/archive/$domain 2>/dev/null || true
            ${pkgs.coreutils}/bin/chmod 644 /etc/letsencrypt/archive/$domain/*.pem 2>/dev/null || true

            echo "[ssl-selfsigned] Active SSL cert: $(readlink -f "$leDir/fullchain.pem")"
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
            domain="${domain}"
            leArchive="/etc/letsencrypt/archive/$domain"
            leDir="/etc/letsencrypt/live/$domain"

            # Fix LE archive permissions
            chmod 755 /etc/letsencrypt/archive /etc/letsencrypt/archive/$domain 2>/dev/null || true
            chmod 644 "$leArchive"/*.pem 2>/dev/null || true

            # Re-symlink the latest LE certs (certbot increments the number)
            latest_cert="$(ls "$leArchive"/cert*.pem 2>/dev/null | sort | tail -1)"
            latest_chain="$(ls "$leArchive"/chain*.pem 2>/dev/null | sort | tail -1)"
            latest_fullchain="$(ls "$leArchive"/fullchain*.pem 2>/dev/null | sort | tail -1)"
            latest_privkey="$(ls "$leArchive"/privkey*.pem 2>/dev/null | sort | tail -1)"
            if [ -n "$latest_fullchain" ] && [ -n "$latest_privkey" ]; then
              echo "[certbot-renew] Updating LE symlinks"
              ln -sf "$latest_cert"      "$leDir/cert.pem"
              ln -sf "$latest_chain"     "$leDir/chain.pem"
              ln -sf "$latest_fullchain" "$leDir/fullchain.pem"
              ln -sf "$latest_privkey"   "$leDir/privkey.pem"
            fi

            # Ensure nginx log files exist and are writable
            touch /var/log/nginx/research.access.log /var/log/nginx/research.error.log 2>/dev/null || true
            chown :nginx /var/log/nginx/research.access.log /var/log/nginx/research.error.log 2>/dev/null || true
            chmod 664 /var/log/nginx/research.access.log /var/log/nginx/research.error.log 2>/dev/null || true

            echo "[certbot-renew] Active SSL cert: $(readlink -f "$leDir/fullchain.pem")"
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
