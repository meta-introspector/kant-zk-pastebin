{ config, lib, pkgs, self, zos-circuit-tile, org-tile, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  kant-pastebin = self.packages.${system}.kant-pastebin;
  index-docs = self.packages.${system}.index-docs;
  tilesDir = "${zos-circuit-tile.packages.${system}.default}/lib:${org-tile.packages.${system}.default}/lib";

  domain = "solana.solfunmeme.com";

  # ─── SSL certificate sources (in order of preference) ───────────────
  # 1. Let's Encrypt (certbot) — used when certbot has been run successfully
  leDir = "/etc/letsencrypt/live/${domain}";
  leCert = "${leDir}/fullchain.pem";
  leKey  = "${leDir}/privkey.pem";

  # 2. Self-signed fallback — used until certbot certifies the domain
  selfSignedDir  = "/mnt/data1/kant/pastebin/ssl";
  selfSignedCert = "${selfSignedDir}/${domain}.crt";
  selfSignedKey  = "${selfSignedDir}/${domain}.key";

  # 3. Active cert — try LE first, fall back to self-signed
  activeCert = if builtins.pathExists leCert then leCert else selfSignedCert;
  activeKey  = if builtins.pathExists leKey  then leKey  else selfSignedKey;

  # ─── Certbot with Namecheap DNS plugin ──────────────────────────────
  # The Namecheap hook binary lives at /usr/local/bin/certbot-namecheap
  # and is triggered by the existing Ubuntu certbot timer.
  # For full Nix-managed renewal we will eventually package the hook:
  # certbotNamecheapPkg = pkgs.stdenv.mkDerivation { ... };
in
{
  config = {
    services.nginx.enable = true;

    # ─── Nginx virtual host ────────────────────────────────────────────
    services.nginx.virtualHosts."${domain}" = {
      serverName = domain;

      # forceSSL = true → auto listen :80 (redirect) + :443 (HTTPS)
      forceSSL = true;

      sslCertificate     = leCert;
      sslCertificateKey  = leKey;

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

    # ─── Generate self-signed fallback certs + symlink to LE path ─────
    # Creates self-signed certs at /mnt/data1/kant/pastebin/ssl/ and
    # symlinks them into /etc/letsencrypt/live/<domain>/ so nginx
    # can start before certbot runs.
    # Once certbot issues real certs they replace these symlinks.
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
            # ── Only create self-signed certs if no LE certs exist ──────
            if [ -f "${leCert}" ] && [ -f "${leKey}" ]; then
              echo "LE certs present at ${leDir} — skipping self-signed"
              exit 0
            fi

            # ── Ensure LE archive dirs are nginx-readable ──────────────
            leArchive="/etc/letsencrypt/archive/${domain}"
            ${pkgs.coreutils}/bin/mkdir -p "${leArchive}" "${selfSignedDir}" "${leDir}"
            ${pkgs.coreutils}/bin/chmod 755 "${selfSignedDir}" "${leArchive}" "${leDir}" 2>/dev/null || true

            # ── Create self-signed cert if not already present ─────────
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

            # ── Symlink self-signed into LE live dir (fallback) ────────
            # Only symlink cert + key that actually exist in the LE schema
            for f in cert.pem chain.pem fullchain.pem; do
              [ -L "${leDir}/$f" ] && continue
              ${pkgs.coreutils}/bin/ln -s "${selfSignedCert}" "${leDir}/$f" 2>/dev/null || true
            done
            [ -L "${leDir}/privkey.pem" ] || \
              ${pkgs.coreutils}/bin/ln -s "${selfSignedKey}" "${leDir}/privkey.pem" 2>/dev/null || true

            # ── Fix up permissions so nginx can read LE archive ────────
            ${pkgs.coreutils}/bin/chmod 755 /etc/letsencrypt/archive /etc/letsencrypt/archive/${domain} 2>/dev/null || true
            ${pkgs.coreutils}/bin/chmod 644 /etc/letsencrypt/archive/${domain}/*.pem 2>/dev/null || true
          '';
        in "${script}";
      };
    };

    # ─── Namecheap DNS-01 credentials (for certbot) ────────────────────
    # The certbot-namecheap binary reads these from env.
    # See: /usr/local/bin/certbot-namecheap-hook
    #      /usr/local/bin/certbot-namecheap (Rust binary)
    environment.etc."certbot/namecheap.env" = {
      text = ''
        # Namecheap API credentials for DNS-01 ACME challenge
        # Used by /usr/local/bin/certbot-namecheap
        # CERTBOT_DOMAIN and CERTBOT_VALIDATION are set by certbot
        NAMECHEAP_API_USER="your_namecheap_username"
        NAMECHEAP_API_KEY="your_namecheap_api_key"
      '';
      mode = "0600";
    };

    # ─── Certbot renewal (delegates to Ubuntu's existing certbot) ──────
    # The existing Ubuntu certbot.timer + namecheap hook handle renewal.
    # These Nix-managed services are ready for when the Ubuntu ones are
    # decommissioned:
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
            # Make LE archive nginx-readable
            chmod 755 /etc/letsencrypt/archive /etc/letsencrypt/archive/solana.solfunmeme.com 2>/dev/null || true
            chmod 644 /etc/letsencrypt/archive/solana.solfunmeme.com/*.pem 2>/dev/null || true
            # Also fix nginx log files (created by nginx at startup)
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

    # ─── Pastebin application ──────────────────────────────────────────
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
        BASE_URL = "https://${domain}";
        NFT_DIR = "/mnt/data1/time-2026/03-march/13/nft_enriched";
        ENRICH_PIPELINE = "/mnt/data1/time-2026/03-march/09/mmgroup-rust/enrich-qid.sh";
        RUST_LOG = "info";
        TILES_DIR = tilesDir;
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

    # ─── Packages available on the system ──────────────────────────────
    environment.systemPackages = with pkgs; [
      curl
      jq
      kubo
      nginx
      openssl
      certbot
    ];
  };
}
