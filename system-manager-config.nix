{ config, lib, pkgs, self, zos-circuit-tile, org-tile, nora-tile, dasl-tiles-rust, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  kant-pastebin = self.packages.${system}.kant-pastebin;
  index-docs = self.packages.${system}.index-docs;
  pipelight-cmd = "${self.packages.${system}.pipelight}/bin/pipelight";
  tilesDir = "${zos-circuit-tile.packages.${system}.default}/lib:${org-tile.packages.${system}.default}/lib:${nora-tile.packages.${system}.default}/lib";
  nora = self.packages.${system}.nora;
  daslTilesRust = dasl-tiles-rust.packages.${system}.default;

  # DASL onboarding script — pushes submodule artifacts to NORA
  daslOnboardScript = pkgs.writeShellScriptBin "dasl-onboard-to-nora" (builtins.readFile ./bin/dasl-onboard-to-nora.sh);

  # DASL CI pipeline script — build, test, fuzz, publish all DASL crates
  daslCiScript = pkgs.writeShellScriptBin "dasl-ci" (builtins.readFile ./bin/dasl-ci.sh);

  # DASL CI dashboard — interactive HTML with live tiles
  daslDashboardHtml = pkgs.writeTextDir "dasl-dashboard.html" (builtins.readFile ./bin/dasl-dashboard.html);

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
          client_max_body_size 0;
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
          proxy_connect_timeout 3600s;
          proxy_buffering off;
          proxy_request_buffering off;
        '';
      };

locations."/nora/health" = {
        proxyPass = "http://127.0.0.1:4000/health";
      };

      # Serve CI pipeline results as static files (build, test, fuzz, perf, coverage)
      locations."=/nora/dashboard" = {
        alias = "${daslDashboardHtml}/dasl-dashboard.html";
        extraConfig = ''
          add_header Cache-Control "no-store";
        '';
      };

      locations."/nora/ci-results/" = {
        alias = "/mnt/data1/nora/ci-results/";
        extraConfig = ''
          autoindex on;
          add_header Cache-Control "no-store";
        '';
      };

      # ─── NotebookLM exports  ────────────────────────────────────────
      # NOTE: Served via /etc/nginx/locations.d/notebooklm.conf
      # (Ubuntu-managed nginx, not system-manager)

      locations."/nora/" = {
        proxyPass = "http://127.0.0.1:4000/";
        proxyWebsockets = false;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;

          # Rewrite HTML/JS/CSS paths to include /nora/ prefix
          sub_filter_types text/html text/css application/javascript;
          sub_filter_once off;
          sub_filter 'href="/ui/' 'href="/nora/ui/';
          sub_filter 'src="/ui/' 'src="/nora/ui/';
          sub_filter 'href="/api-docs' 'href="/nora/api-docs';
          sub_filter 'action="/ui/' 'action="/nora/ui/';
          sub_filter '</nav>' '
            <div class="border-t border-slate-700 mt-4 pt-4">
              <div class="text-xs font-semibold text-slate-400 uppercase tracking-wider px-4 mb-3">DASL CI</div>
              <a href="/nora/dashboard" class="flex items-center px-4 py-3 text-sm font-medium rounded-lg transition-colors text-slate-300 hover:bg-slate-700 hover:text-white">
                <svg class="w-5 h-5 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z"/></svg>
                Dashboard
              </a>
              <a href="/nora/ci-results/" class="flex items-center px-4 py-3 text-sm font-medium rounded-lg transition-colors text-slate-300 hover:bg-slate-700 hover:text-white">
                <svg class="w-5 h-5 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/></svg>
                Results
              </a>
</div>
           </nav>'
         '';
       };

       # ─── DASL Tile Dashboard (test-result-tile :8081) ───────────────
       locations."/tiles/" = {
         proxyPass = "http://127.0.0.1:8081/";
         proxyWebsockets = true;
         extraConfig = ''
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
           proxy_read_timeout 120s;
         '';
       };

       locations."/dynamic" = {
         proxyPass = "http://127.0.0.1:8081/dynamic";
         extraConfig = ''
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
         '';
       };

       locations."/api/" = {
         proxyPass = "http://127.0.0.1:8081/api/";
         extraConfig = ''
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
         '';
       };

       locations."/tile/ebpf/" = {
         proxyPass = "http://127.0.0.1:18090/ebpf/";
         extraConfig = ''
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
         '';
       };

       locations."/tile/search/" = {
         proxyPass = "http://127.0.0.1:18090/search/";
         extraConfig = ''
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
         '';
       };

       locations."/dashboard/ebpf" = {
         proxyPass = "http://127.0.0.1:18090/dashboard/ebpf";
         extraConfig = ''
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
         '';
       };

       locations."/dashboard/search" = {
         proxyPass = "http://127.0.0.1:18090/dashboard/search";
         extraConfig = ''
           proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
          '';
        };

        locations."/monitoring/check" = {
          proxyPass = "http://127.0.0.1:18090/monitoring/check";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
          '';
        };

        locations."/dashboard/monitoring" = {
          proxyPass = "http://127.0.0.1:18090/dashboard/monitoring";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
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
            ${pkgs.coreutils}/bin/mkdir -p "''${leArchive}" "${selfSignedDir}" "${leDir}"
            ${pkgs.coreutils}/bin/chmod 755 "${selfSignedDir}" "''${leArchive}" "${leDir}" 2>/dev/null || true

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

    # ─── NORA cargo registry config for all Rust builds ────────────
    # Replaces crates.io with local nora registry for sandboxed builds.
    # Apply via: export CARGO_HOME=/etc/nora-cargo; cargo build
    environment.etc."nora-cargo/config.toml" = {
      text = ''
        # Nora cargo registry — replaces crates.io with local registry
        # See ~/dasl/index/nora.txt line215 for the pattern definition
        [source.crates-io]
        replace-with = "nora"

        [source.nora]
        registry = "http://127.0.0.1:4000/cargo/index"
      '';
      mode = "0644";
    };

    # ─── NORA configuration file ─────────────────────────────────────────
    environment.etc."nora/config.toml" = {
      text = ''
        # NORA Configuration — Artifact Registry for DASL ecosystem
        # Serves: Cargo, Go, npm, PyPI, Raw artifacts from ~/dasl/ submodules
        [server]
        host = "127.0.0.1"
        port = 4000
        public_url = "https://solana.solfunmeme.com/nora"
        body_limit_mb = 4096

        [storage]
        mode = "local"
        path = "/mnt/data1/nora/storage"

        [cargo]
        enabled = true
        proxy = "https://index.crates.io"
        proxy_timeout = 60

        [go]
        enabled = true
        proxy = "https://proxy.golang.org"
        proxy_timeout = 60
        proxy_timeout_zip = 300
        max_zip_size = 2147483648

        [npm]
        enabled = true
        proxy = "https://registry.npmjs.org"
        proxy_timeout = 60

        [pypi]
        enabled = true
        proxy = "https://pypi.org/simple/"
        proxy_timeout = 60

        [raw]
        enabled = true
        max_file_size = 2147483648
        cache_control = "no-cache"

        [docker]
        enabled = false

        [registries]
        enable = ["cargo", "go", "npm", "pypi", "raw"]
      '';
      mode = "0644";
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
        TimeoutStartSec = 0;
        TimeoutStopSec = 0;
        TimeoutAbortSec = 0;
        TimeoutSec = 0;
      };
      environment = {
        BIND_ADDR = "127.0.0.1:8090";
        UUCP_SPOOL = "/mnt/data1/spool/uucp/pastebin";
        BASE_PATH = "/pastebin";
        BASE_URL = "https://${domain}";
        NFT_DIR = "/mnt/data1/time-2026/03-march/13/nft_enriched";
        ENRICH_PIPELINE = "/mnt/data1/time-2026/03-march/09/mmgroup-rust/enrich-qid.sh";
        PIPELIGHT_CMD = pipelight-cmd;
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

    # ─── NORA systemd service ───────────────────────────────────────────
    systemd.services.nora = {
      enable = true;
      description = "NORA Artifact Registry — Cargo, Docker, npm, ...";
      after = [ "network-online.target" "nginx.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "system-manager.target" ];

      serviceConfig = {
        Type = "simple";
        User = "nora";
        Group = "nora";
        ExecStart = "${nora}/bin/nora serve";
        Restart = "on-failure";
        RestartSec = "5";
        WorkingDirectory = "/mnt/data1/nora";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
      };

      environment = {
        RUST_LOG = "info";
        NORA_HOST = "127.0.0.1";
        NORA_PORT = "4000";
        NORA_STORAGE_PATH = "/mnt/data1/nora/storage";
        NORA_CONFIG_PATH = "/mnt/data1/nora/config/nora.toml";
      };
    };

    # ─── NORA data directory setup (oneshot) ────────────────────────────
    systemd.services.nora-dir = {
      enable = true;
      description = "Create NORA data directories";
      before = [ "nora.service" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /mnt/data1/nora/{storage,config}
        cp -n /etc/nora/config.toml /mnt/data1/nora/config/nora.toml 2>/dev/null || true
        chown -R nora:nora /mnt/data1/nora
      '';
    };

    # ─── DASL CI pipeline systemd services ──────────────────────────────
    systemd.services.nora-dasl-ci = {
      enable = true;
      description = "DASL CI Pipeline — build, test, fuzz, and publish all DASL crates to NORA";
      after = [ "nora.service" "network-online.target" ];
      requires = [ "nora.service" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "mdupont";
        Group = "mdupont";
        WorkingDirectory = "/home/mdupont/dasl";
        ExecStart = "${daslCiScript}";
        StandardOutput = "journal";
        StandardError = "journal";
        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
      environment = {
        NORA_CI_RESULTS = "/mnt/data1/nora/ci-results";
        DASL_TESTING = "/home/mdupont/dasl/dasl-testing";
        DASL_ROOT = "/home/mdupont/dasl";
        NORA_URL = "http://127.0.0.1:4000";
        NORA_CARGO_CONFIG = "/etc/nora-cargo";
        RUST_LOG = "info";
        # Point cargo to nora registry for any direct cargo commands
        CARGO_HOME = "/etc/nora-cargo";
      };
    };

    systemd.timers.nora-dasl-ci = {
      enable = true;
      description = "Daily DASL CI pipeline run";
      wants = [ "nora-dasl-ci.service" ];
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "600";
      };
    };

    # ─── DASL → NORA onboarding service ───────────────────────────
    systemd.services.nora-dasl-onboard = {
      enable = true;
      description = "Onboard DASL submodule artifacts into NORA";
      after = [ "nora.service" "network-online.target" ];
      requires = [ "nora.service" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "nora";
        Group = "nora";
        ExecStart = "${daslOnboardScript}";
        StandardOutput = "journal";
        StandardError = "journal";
        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
      };
      environment = {
        NORA_URL = "http://127.0.0.1:4000";
        DASL_ROOT = "/home/mdupont/dasl";
        RUST_LOG = "info";
      };
    };

    systemd.timers.nora-dasl-onboard = {
      enable = true;
      description = "Daily DASL → NORA artifact sync";
      wants = [ "nora-dasl-onboard.service" ];
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "7200";
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
      nora
      daslOnboardScript
      daslCiScript
    ];

    # ─── IPLD CAR-of-CARs shmem server ────────────────────────────────
    # Content-addressed block store with token-level dedup.
    # Runs as ipld-data user (not root). Non-sparse pages.car.
    systemd.services.ipld-car-shmem = {
      enable = true;
      description = "IPLD CAR-of-CARs Shared Memory Server — content-addressed block store with token dedup";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];

      serviceConfig = {
        Type = "simple";
        User = "ipld-data";
        Group = "ipld-data";
        ExecStart = "/home/mdupont/dasl/ipld-car-ipc-shmem-linux/target/release/ipld-car-shmem-server";
        Restart = "on-failure";
        RestartSec = "5";
        WorkingDirectory = "/mnt/data1/dasl-cache";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
      };

      environment = {
        IPLD_CAR_CACHE_PATH = "/mnt/data1/dasl-cache";
        IPLD_CAR_CAPACITY = "2147483648"; # 2GB, non-sparse
        RUST_LOG = "info";
      };
    };

# ─── IPLD data directory setup (oneshot) ────────────────────────
     systemd.services.ipld-car-shmem-dir = {
       enable = true;
       description = "Create IPLD CAR data directories";
       before = [ "ipld-car-shmem.service" ];
       wantedBy = [ "system-manager.target" ];
       serviceConfig = {
         Type = "oneshot";
         RemainAfterExit = true;
       };
       script = ''
         mkdir -p /mnt/data1/dasl-cache
         chown -R ipld-data:ipld-data /mnt/data1/dasl-cache
       '';
     };

# ─── DASL Tile Server (surface-pane + tile-server) ───────────────
      systemd.services.dasl-tile-server = {
        enable = true;
        description = "DASL Tile Server — eBPF + search endpoints";
        after = [ "network.target" ];
        wantedBy = [ "system-manager.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${daslTilesRust}/bin/tile-server -d solana.solfunmeme.com -p 18090";
          Restart = "always";
          RestartSec = "10";
          WorkingDirectory = "/home/mdupont/dasl-tiles-rust";
          Environment = "DASL_TESTING_ROOT=/mnt/data1/time-2026/02-february/22/dasl/dasl-testing";
          TimeoutStartSec = 0;
          TimeoutStopSec = 0;
        };
      };

      # ─── Test Result Tile Dashboard (port 8081) ────────────────────
      systemd.services.test-result-tile = {
        enable = true;
        description = "DASL Test Result Tile — 247 tiles across harnesses + dynamic services";
        after = [ "network.target" "ipld-car-shmem.service" ];
        wantedBy = [ "system-manager.target" ];
        serviceConfig = {
          Type = "simple";
          User = "dasl";
          Group = "dasl";
          ExecStart = "${daslTilesRust}/bin/tile-server serve --domain solana.solfunmeme.com --port 8081 --base-path /tiles";
          Restart = "always";
          RestartSec = "10s";
          WorkingDirectory = "/var/lib/dasl-tiles/test-result-tile";
          StandardOutput = "journal";
          StandardError = "journal";
          NoNewPrivileges = true;
          PrivateTmp = true;
        };
        environment = {
          RUST_LOG = "info";
          DASL_TILES_DIR = "/var/lib/dasl-tiles/test-result-tile/public";
          IPLD_CAR_SHMEM = "/run/ipld-car-shmem";
          DASL_TESTING_ROOT = "/mnt/data1/time-2026/02-february/22/dasl/dasl-testing";
        };
      };
    };
  }
