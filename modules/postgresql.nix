{ config, lib, pkgs, ... }:

let
  cfg = config.services.postgresql;
  pg = cfg.package;
  pgdata = cfg.dataDir;
  pglog  = cfg.logDir + "/postgresql.log";
  port   = toString cfg.port;
in
{
  options.services.postgresql = {
    enable = lib.mkEnableOption "PostgreSQL database server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.postgresql_16;
      description = "PostgreSQL package to use";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/data1/postgres/14/main";
      description = "PostgreSQL data directory";
    };

    logDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/postgresql";
      description = "PostgreSQL log directory";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 5432;
      description = "PostgreSQL listening port";
    };

    authentication = lib.mkOption {
      type = lib.types.str;
      default = ''
        local all all trust
        host  all all 127.0.0.1/32 trust
        host  all all ::1/128      trust
      '';
      description = "pg_hba.conf authentication rules";
    };

    extraConfig = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Extra postgresql.conf settings";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 postgres postgres -"
      "d ${cfg.logDir}  0755 postgres postgres -"
    ];

    systemd.services.postgresql = {
      enable = true;
      description = "PostgreSQL database server (managed via system-manager)";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      preStart = let
        script = pkgs.writeShellScript "postgresql-pre-start" ''
          set -eu
          if [ ! -f "${cfg.dataDir}/PG_VERSION" ]; then
            echo "Initializing PostgreSQL cluster at ${cfg.dataDir}..."
            mkdir -p "${cfg.dataDir}"
            chown postgres:postgres "${cfg.dataDir}"
            chmod 0700 "${cfg.dataDir}"
            ${cfg.package}/bin/initdb -D "${cfg.dataDir}" --auth=trust --encoding=UTF8
          fi
        '';
      in "${script}";
      serviceConfig = {
        Type = "forking";
        User = "postgres";
        Group = "postgres";
        UMask = "0077";
        PIDFile = "${cfg.dataDir}/postmaster.pid";
        ExecStart = "${cfg.package}/bin/pg_ctl start -D ${cfg.dataDir} -l ${pglog} -o '-p ${port}'";
        ExecStop  = "${cfg.package}/bin/pg_ctl stop  -D ${cfg.dataDir} -m fast";
        ExecReload = "${cfg.package}/bin/pg_ctl reload -D ${cfg.dataDir}";
        TimeoutSec = 300;
      };
      postStart = let
        script = pkgs.writeShellScript "postgresql-post-start" ''
          set -eu
          # Write pg_hba.conf from config
          cat > "${cfg.dataDir}/pg_hba.conf" <<-EOF
          # PostgreSQL Client Authentication — managed by system-manager
          ${cfg.authentication}
          EOF
          # Apply extra config
          ${lib.optionalString (cfg.extraConfig != "") ''
            echo "${cfg.extraConfig}" >> "${cfg.dataDir}/postgresql.conf"
          ''}
          # Reload to apply auth changes
          ${cfg.package}/bin/pg_ctl reload -D "${cfg.dataDir}" || true
        '';
      in "${script}";
    };
  };
}

