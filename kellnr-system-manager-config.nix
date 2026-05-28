{ config, lib, pkgs, self, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  kellnr = self.packages.${system}.kellnr;

  domain = "kellnr.solfunmeme.com";
  dataDir = "/mnt/data1/kellnr";

  pgPort = 5432;
  pgUser = "kellnr";
  pgDb   = "kellnr";

  # ─── SSL certificate sources (in order of preference) ───────────────
  leDir = "/etc/letsencrypt/live/${domain}";
  leCert = "${leDir}/fullchain.pem";
  leKey  = "${leDir}/privkey.pem";
  selfSignedDir  = "/mnt/data1/kellnr/ssl";
  selfSignedCert = "${selfSignedDir}/${domain}.crt";
  selfSignedKey  = "${selfSignedDir}/${domain}.key";
  activeCert = if builtins.pathExists leCert then leCert else selfSignedCert;
  activeKey  = if builtins.pathExists leKey  then leKey  else selfSignedKey;
in
{
  config = {
    # ─── PostgreSQL (system-manager module) ──────────────────────────
    services.postgresql = {
      enable = true;
      port = pgPort;
      dataDir = "/mnt/data1/postgres/14/main";
    };

    # ─── Nginx reverse proxy ─────────────────────────────────────────
    services.nginx.enable = true;

    services.nginx.virtualHosts."${domain}" = {
      serverName = domain;
      forceSSL = true;
      sslCertificate     = leCert;
      sslCertificateKey  = leKey;

      locations."/" = {
        proxyPass = "http://127.0.0.1:8000/";
        proxyWebsockets = false;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_buffering off;
          proxy_request_buffering off;
          client_max_body_size 500m;
        '';
      };
    };

    # ─── Self-signed fallback certs ──────────────────────────────────
    systemd.services.ssl-selfsigned-kellnr = {
      enable = true;
      description = "Generate self-signed SSL fallback certificate for ${domain}";
      before = [ "nginx.service" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = let
          script = pkgs.writeShellScript "ssl-selfsigned-kellnr" ''
            set -eu
            ${pkgs.coreutils}/bin/mkdir -p "${selfSignedDir}" "${leDir}"
            ${pkgs.coreutils}/bin/chmod 755 "${selfSignedDir}" "${leDir}"
            ${pkgs.coreutils}/bin/rm -f "${leCert}" "${leKey}"
            ${pkgs.openssl}/bin/openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
              -keyout "${selfSignedKey}.tmp" -out "${selfSignedCert}.tmp" \
              -subj /CN=${domain} 2>/dev/null
            ${pkgs.coreutils}/bin/mv "${selfSignedKey}.tmp" "${selfSignedKey}"
            ${pkgs.coreutils}/bin/mv "${selfSignedCert}.tmp" "${selfSignedCert}"
            ${pkgs.coreutils}/bin/chmod 644 "${selfSignedCert}"
            ${pkgs.coreutils}/bin/chmod 644 "${selfSignedKey}"
            ${pkgs.coreutils}/bin/ln -sf "${selfSignedCert}" "${leCert}"
            ${pkgs.coreutils}/bin/ln -sf "${selfSignedKey}" "${leKey}"
          '';
        in "${script}";
      };
    };

    # ─── Database setup: create kellnr user + database ───────────────
    systemd.services.kellnr-db-setup = {
      enable = true;
      description = "Create kellnr PostgreSQL user and database";
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      before = [ "kellnr.service" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "postgres";
        ExecStart = let
          script = pkgs.writeShellScript "kellnr-db-setup" ''
            set -eu
            # Create user (ignore error if already exists)
            ${config.services.postgresql.package}/bin/psql -p ${toString pgPort} -tc \
              "SELECT 1 FROM pg_roles WHERE rolname='${pgUser}'" | grep -q 1 \
              || ${config.services.postgresql.package}/bin/psql -p ${toString pgPort} -c \
                 "CREATE ROLE ${pgUser} LOGIN PASSWORD 'kellnr_pg_password';"

            # Create database (ignore error if already exists)
            ${config.services.postgresql.package}/bin/psql -p ${toString pgPort} -tc \
              "SELECT 1 FROM pg_database WHERE datname='${pgDb}'" | grep -q 1 \
              || ${config.services.postgresql.package}/bin/psql -p ${toString pgPort} -c \
                 "CREATE DATABASE ${pgDb} OWNER ${pgUser};"
          '';
        in "${script}";
      };
    };

    # ─── Kellnr application service ────────────────────────────────────
    systemd.services.kellnr = {
      enable = true;
      description = "Kellnr - Self-hosted Rust crate registry";
      after = [ "network.target" "postgresql.service" "kellnr-db-setup.service" ];
      requires = [ "postgresql.service" "kellnr-db-setup.service" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${kellnr}/bin/kellnr";
        Restart = "always";
        RestartSec = "10";
        WorkingDirectory = dataDir;
        User = "kellnr";
        Group = "kellnr";
        StateDirectory = "kellnr";
        StateDirectoryMode = "0750";
      };
      environment = {
        KELLNR_DATA_DIR = "${dataDir}/data";
        KELLNR_HOST = "127.0.0.1";
        KELLNR_PORT = "8000";
        KELLNR_DOMAIN = domain;
        KELLNR_REGISTRY_OVERWRITE = "true";

        # PostgreSQL (replaces default SQLite)
        KELLNR_POSTGRESQL__ENABLED = "true";
        KELLNR_POSTGRESQL__ADDRESS = "127.0.0.1";
        KELLNR_POSTGRESQL__PORT = toString pgPort;
        KELLNR_POSTGRESQL__DB = pgDb;
        KELLNR_POSTGRESQL__USER = pgUser;
        KELLNR_POSTGRESQL__PWD = "kellnr_pg_password";

        RUST_LOG = "info";
      };
    };

    # ─── Data directory setup ────────────────────────────────────────
    systemd.tmpfiles.rules = [
      "d ${dataDir} 0750 kellnr kellnr -"
      "d ${dataDir}/data 0750 kellnr kellnr -"
    ];

    # ─── Packages available on the system ────────────────────────────
    environment.systemPackages = with pkgs; [
      curl
      jq
      nginx
      openssl
      postgresql_16
    ];

    # ─── Create kellnr user ──────────────────────────────────────────
    users.users.kellnr = {
      isSystemUser = true;
      group = "kellnr";
      description = "Kellnr crate registry service user";
      home = dataDir;
      createHome = true;
    };

    users.groups.kellnr = {};
  };
}
