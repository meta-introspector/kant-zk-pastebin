{ config, lib, pkgs, pastebin-src, nora-src, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  kant-pastebin = pastebin-src.packages.${system}.kant-pastebin;
  nora = nora-src.packages.${system}.default;
in
{
  config = {
    users.groups.kant.gid = 30036;
    users.users.kant = {
      uid = 942;
      isSystemUser = true;
      group = "kant";
      home = "/srv/kant";
      createHome = true;
      homeMode = "0755";
      extraGroups = [ "mdupont" ];
      shell = "${pkgs.bash}/bin/bash";
    };

    users.groups.nora.gid = 30038;
    users.users.nora = {
      uid = 944;
      isSystemUser = true;
      group = "nora";
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

    systemd.services.svg2anim-worker = {
      enable = true;
      description = "SVG to Animated GIF Worker";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "kant";
        Group = "kant";
        SupplementaryGroups = [ "mdupont" ];
        WorkingDirectory = "/mnt/data1/kant/pastebin";
        ExecStart = "${kant-pastebin}/bin/bash /mnt/data1/kant/pastebin/scripts/svg2anim-worker.sh";
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
        UUCP_SPOOL = "/srv/kant/svg-spool";
        SVG2ANIM_FRAMES_BIN = "/mnt/data1/time-2026/06-june/26/svg2anim-frames/target/release/svg2anim-frames";
        SVG2ANIM_FPS = "5";
        SVG2ANIM_MAX_WIDTH = "1920";
        SVG2ANIM_MAX_HEIGHT = "1200";
      };
    };

    # ─── Nora Data Dir ──────────────────────────────────────
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
        install -m 644 ${pkgs.writeText "nora.toml" ''
          [server]
          host = "127.0.0.1"
          port = 4000

          [storage]
          mode = "local"
          path = "/mnt/data1/nora/storage"

          [auth]
          enabled = false
          anonymous_read = true

          [cargo]
          enabled = true
          proxy = "https://crates.io"
          proxy_timeout = 30

          [docker]
          enabled = false

          [npm]
          enabled = false

          [pypi]
          enabled = false

          [registries]
          enable = ["cargo"]

          [rate_limit]
          enabled = false
        ''} /mnt/data1/nora/config/nora.toml
        chown -R nora:nora /mnt/data1/nora
      '';
    };

    # ─── Nora Registry (:4000) ──────────────────────────────
    systemd.services.nora = {
      enable = true;
      description = "NORA Artifact Registry — Cargo, Docker, npm, ...";
      after = [ "network-online.target" "nora-dir.service" ];
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
        NORA_PUBLIC_URL = "https://solana.solfunmeme.com/nora/";
        NORA_RATE_LIMIT_ENABLED = "false";
      };
    };

    systemd.tmpfiles.rules = [
      "d /srv/kant/svg-spool 0755 kant kant -"
      "d /srv/kant/svg-spool/svg2anim-jobs 0755 kant kant -"
      "d /srv/kant/svg-spool/svg2anim-results 0755 kant kant -"
      "d /var/spool/uucp/pastebin 0755 kant kant -"
    ];
  };
}
