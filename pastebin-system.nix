{ config, lib, pkgs, pastebin-src, nora-src, dasl-tiles-rust, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  HOME = "/home/mdupont";
  DOCS = "${HOME}/DOCS";
  domain = "solana.solfunmeme.com";
  kant-pastebin = pastebin-src.packages.${system}.kant-pastebin;
  nora = nora-src.packages.${system}.default;
  daslTilesRust = dasl-tiles-rust.packages.${system}.tile-server;
  DASL_TESTING = "${HOME}/dasl/dasl-testing";
  # Nix store binaries — built from flakes in ~/dasl/dasl-testing/harnesses/
  SERDE   = "/nix/store/r1x7czr8yxc5c3lbq5qnibzm18sjmc65-dasl-service-serde-ipld-dagcbor-0.1.0";
  N0      = "/nix/store/12f3zpbyk6sm2ywzd1axa33fhjmwa0ds-dasl-service-n0-dasl-0.1.0";
  LIBIPLD = "/nix/store/s1wdbhksxppmchciy3j4xc48sw4sfbja-dasl-service-libipld-0.1.0";
  QA      = "/nix/store/j0h7lv10pixirs2xqzva2x9yxbxg5czc-dasl-qa-team-tile-0.1.0";
  FUZZ    = "/nix/store/psgg003ykzx4gi82njbw001w7bnq9ff5-dasl-fuzz-team-tile-0.1.0";
  LEAN4_CBOR = "${HOME}/dasl/ipld-car-ipc-shmem-linux/target/release/lean4-cbor-bridge";
  LEAN4_REPL = "${HOME}/dasl/ipld-car-ipc-shmem-linux/target/release/lean4-repl";
  STATICSPLIT_JSON = "/nix/store/4iglmyjm8ykkz8cya16k2xmzx7kb04c3-staticsplitjson/bin/staticsplitjson";
  LEAN4_INTROSPECTOR_BIN = "/nix/store/9a8fxa2503c2qfah96nbrl3l78628pkr-lean4introspector/bin/lean4introspector";
  LEAN4_DATA = "/var/lib/lean4-cbor-bridge";
in
{
  config = {
    # ═══════════════════════════════════════════════════════════
    # Users & Groups
    # ═══════════════════════════════════════════════════════════
    users.groups.dasl.gid = 30037;
    users.users.dasl = { uid = 943; isSystemUser = true; group = "dasl"; };
    users.groups.kant.gid = 30036;
    users.users.kant = {
      uid = 942; isSystemUser = true; group = "kant";
      home = "/srv/kant"; createHome = true; homeMode = "0755";
      extraGroups = [ "mdupont" ];
      shell = "${pkgs.bash}/bin/bash";
    };
    users.groups.zombie.gid = 30905;
    users.users.zombie = { uid = 905; isSystemUser = true; group = "zombie"; };
    users.groups.nginx.gid = 1000;
    users.users.nginx = { uid = 1000; group = "nginx"; isSystemUser = true; };
    users.groups.www-data.gid = 33;
    users.users.www-data = { uid = 33; group = "www-data"; };
    users.groups.nora.gid = 30038;
    users.users.nora = { uid = 944; isSystemUser = true; group = "nora"; };

    # ═══════════════════════════════════════════════════════════
    # Tmpfiles
    # ═══════════════════════════════════════════════════════════
    systemd.tmpfiles.rules = [
      "d /var/spool/uucp/pastebin 0755 kant kant -"
      "d /run/nginx 0755 www-data www-data -"
      "d /srv/kant/svg-spool 0755 kant kant -"
      "d /srv/kant/svg-spool/svg2anim-jobs 0755 kant kant -"
      "d /srv/kant/svg-spool/svg2anim-results 0755 kant kant -"
    ];

    # ═══════════════════════════════════════════════════════════
    # Kant Pastebin (:8090)
    # ═══════════════════════════════════════════════════════════
    systemd.services.kant-pastebin = {
      enable = true;
      description = "Kant Pastebin - UUCP + zkTLS + IPFS";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple"; User = "kant"; Group = "kant";
        SupplementaryGroups = [ "mdupont" ];
        WorkingDirectory = "/mnt/data1/kant/pastebin";
        ExecStart = "${kant-pastebin}/bin/kant-pastebin";
        Restart = "always"; RestartSec = "10";
        TimeoutStartSec = 0; TimeoutStopSec = 0; TimeoutAbortSec = 0; TimeoutSec = 0;
        StandardOutput = "journal"; StandardError = "journal";
        NoNewPrivileges = true; PrivateTmp = true; PrivateDevices = true;
        ProtectKernelTunables = true; ProtectKernelModules = true; ProtectControlGroups = true;
      };
      environment = {
        BIND_ADDR = "127.0.0.1:8090";
        UUCP_SPOOL = "/var/spool/uucp/pastebin";
        BASE_PATH = "/pastebin";
        BASE_URL = "https://solana.solfunmeme.com";
        NFT_DIR = "/mnt/data1/time-2026/03-march/13/nft_enriched";
        ENRICH_PIPELINE = "/mnt/data1/time-2026/03-march/09/mmgroup-rust/enrich-qid.sh";
        RUST_LOG = "info"; TILES_DIR = "";
      };
    };

    # ═══════════════════════════════════════════════════════════
    # SVG2Anim Worker
    # ═══════════════════════════════════════════════════════════
    systemd.services.svg2anim-worker = {
      enable = true;
      description = "SVG to Animated GIF Worker";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple"; User = "kant"; Group = "kant";
        SupplementaryGroups = [ "mdupont" ];
        WorkingDirectory = "/mnt/data1/kant/pastebin";
        ExecStart = "${kant-pastebin}/bin/bash /mnt/data1/kant/pastebin/scripts/svg2anim-worker.sh";
        Restart = "always"; RestartSec = "10";
        TimeoutStartSec = 0; TimeoutStopSec = 0; TimeoutAbortSec = 0; TimeoutSec = 0;
        StandardOutput = "journal"; StandardError = "journal";
        NoNewPrivileges = true; PrivateTmp = true; PrivateDevices = true;
        ProtectKernelTunables = true; ProtectKernelModules = true; ProtectControlGroups = true;
      };
      environment = {
        UUCP_SPOOL = "/srv/kant/svg-spool";
        SVG2ANIM_FRAMES_BIN = "/mnt/data1/time-2026/06-june/26/svg2anim-frames/target/release/svg2anim-frames";
        SVG2ANIM_FPS = "5"; SVG2ANIM_MAX_WIDTH = "1920"; SVG2ANIM_MAX_HEIGHT = "1200";
      };
    };

    # ═══════════════════════════════════════════════════════════
    # Nora Registry (:4000)
    # ═══════════════════════════════════════════════════════════
    systemd.services.nora-dir = {
      enable = true;
      description = "Create NORA data directories";
      before = [ "nora.service" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
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

    systemd.services.nora = {
      enable = true;
      description = "NORA Artifact Registry — Cargo, Docker, npm, ...";
      after = [ "network-online.target" "nora-dir.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple"; User = "nora"; Group = "nora";
        ExecStart = "${nora}/bin/nora serve";
        Restart = "on-failure"; RestartSec = "5";
        WorkingDirectory = "/mnt/data1/nora";
        NoNewPrivileges = true; PrivateTmp = true; PrivateDevices = true;
        ProtectKernelTunables = true; ProtectKernelModules = true; ProtectControlGroups = true;
      };
      environment = {
        RUST_LOG = "info"; NORA_HOST = "127.0.0.1"; NORA_PORT = "4000";
        NORA_STORAGE_PATH = "/mnt/data1/nora/storage";
        NORA_CONFIG_PATH = "/mnt/data1/nora/config/nora.toml";
        NORA_PUBLIC_URL = "https://solana.solfunmeme.com/nora/";
        NORA_RATE_LIMIT_ENABLED = "false";
      };
    };

    # ═══════════════════════════════════════════════════════════
    # Tier 1: Infrastructure Tiles (Python — DOCS/)
    # ═══════════════════════════════════════════════════════════
    systemd.services.nagios-tile-monitor = {
      enable = true;
      description = "Nagios-style DASL Tile Monitor";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple"; User = "dasl"; Group = "dasl";
        ExecStart = "${pkgs.python3}/bin/python3 ${DOCS}/nagios-tile-server.py --port 8800";
        Restart = "always"; RestartSec = "5";
        NoNewPrivileges = true; PrivateTmp = true;
      };
      environment = { HOME = HOME; };
    };

    systemd.services.deploy-tile = {
      enable = true;
      description = "Deploy Tile — system-manager control panel";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple"; User = "dasl"; Group = "dasl";
        ExecStart = "${pkgs.python3}/bin/python3 ${DOCS}/deploy-tile-server.py --port 8810";
        Restart = "always"; RestartSec = "5";
        NoNewPrivileges = true; PrivateTmp = true;
      };
      environment = { HOME = HOME; };
    };

    systemd.services.vendormod-tile-server = {
      enable = true;
      description = "Vendormod Tile Server — modules, refactor, DASL badges";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple"; User = "dasl"; Group = "dasl";
        ExecStart = "${pkgs.python3}/bin/python3 ${DOCS}/vendormod-tile-server.py --port 8765";
        Restart = "always"; RestartSec = "5";
        NoNewPrivileges = true; PrivateTmp = true;
      };
      environment = { HOME = HOME; };
    };

    systemd.services.task-runner-tile-server = {
      enable = true;
      description = "Task Runner Tile — fallback manifest server for /task-runner/";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple"; User = "mdupont"; Group = "mdupont";
        ExecStart = "${pkgs.python3}/bin/python3 ${HOME}/dasl-planning/scripts/task-runner-tile-server.py";
        Restart = "always"; RestartSec = "5";
        NoNewPrivileges = true; PrivateTmp = true;
      };
      environment = { HOME = HOME; };
    };

    systemd.services.port-registry-tile = {
      enable = true;
      description = "Port Registry Tile — DASL tile port/catalog registry";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple"; User = "dasl"; Group = "dasl";
        ExecStart = "${pkgs.python3}/bin/python3 ${DOCS}/port-registry-tile-server.py --port 8820";
        Restart = "always"; RestartSec = "5";
        NoNewPrivileges = true; PrivateTmp = true;
      };
      environment = { HOME = HOME; };
    };

    systemd.services.coverage-tile = {
      enable = true;
      description = "DASL Coverage Proof Tile — corpus coverage matrix + perf traces";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple"; User = "dasl"; Group = "dasl";
        ExecStart = "${pkgs.python3}/bin/python3 ${DOCS}/coverage-tile-server.py";
        Restart = "always"; RestartSec = "5";
        NoNewPrivileges = true; PrivateTmp = true;
      };
      environment = { HOME = HOME; };
    };

    # ═══════════════════════════════════════════════════════════
    # Lean4 Services
    # ═══════════════════════════════════════════════════════════
    systemd.services.lean4-cbor-bridge = {
      enable = true;
      description = "Lean4 → DAG-CBOR Bridge";
      after = [ "network.target" "ipld-car-shmem.service" ];
      wants = [ "ipld-car-shmem.service" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple"; User = "dasl"; Group = "dasl";
        StateDirectory = "lean4-cbor-bridge";
        WorkingDirectory = "${LEAN4_DATA}";
        ExecStart = "${LEAN4_CBOR} --port 8155 --introspector ${LEAN4_INTROSPECTOR_BIN}";
        Restart = "always"; RestartSec = "5";
        StandardOutput = "journal"; StandardError = "journal";
        NoNewPrivileges = true; PrivateTmp = true; PrivateDevices = true;
        ProtectHome = "read-only"; ProtectSystem = "strict";
      };
      environment = {
        LEAN4_INTROSPECTOR = "${LEAN4_INTROSPECTOR_BIN}";
        DATA_DIR = "${LEAN4_DATA}"; RUST_LOG = "info";
      };
    };

    systemd.services.lean4-repl = {
      enable = true;
      description = "Lean4 IPLD REPL — persistent context + fuzzy linker";
      after = [ "network.target" "ipld-car-shmem.service" ];
      wants = [ "ipld-car-shmem.service" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple"; User = "dasl"; Group = "dasl";
        WorkingDirectory = "/tmp";
        ExecStart = "${LEAN4_REPL} --port 8156";
        Restart = "always"; RestartSec = "5";
        StandardOutput = "journal"; StandardError = "journal";
        NoNewPrivileges = true; PrivateTmp = true;
        ProtectHome = "read-only"; ProtectSystem = "strict";
      };
      environment = {
        STATIC_SPLIT_BIN = "${STATICSPLIT_JSON}";
        ARISTOTLE_API_KEY = ""; RUST_LOG = "info";
        SHMEM_NAMESPACE = "lean4";
        PATH = lib.mkForce "/nix/store/aqpyjzpqhs988lpqs8rnq8rw3i7ihrmi-lean/bin:/home/mdupont/.nix-profile/bin:/run/current-system/sw/bin";
      };
    };

    # ═══════════════════════════════════════════════════════════
    # Tier 2: DASL Tiles Rust (:18090)
    # ═══════════════════════════════════════════════════════════
    systemd.services.d8-2a-monitor = {
      enable = false;
      description = "D8-2A eBPF Profiler (disabled — use scoped profiler)";
      after = [ "local-fs.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple"; User = "root"; Group = "root";
        ExecStart = "/mnt/data1/nix/vendor/rust/cargo2nix/submodules/cargo-clean/tools/cargo-vendormod/aya-nix/target/release/d8_2a_loader /mnt/data1/nix/vendor/rust/cargo2nix/submodules/cargo-clean/tools/cargo-vendormod/aya-nix/target/bpfel-unknown-none/release/libd8_2a_monitor.so";
        Restart = "always"; RestartSec = "10";
        StandardOutput = "journal"; StandardError = "journal";
      };
    };

    systemd.services.dasl-tiles-rust = {
      enable = true;
      description = "DASL Tile Webview — eBPF D8-2A Monitor";
      after = [ "network.target" "d8-2a-monitor.service" ];
      wants = [ "d8-2a-monitor.service" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple"; User = "dasl"; Group = "dasl";
        ExecStart = "${daslTilesRust}/bin/tile-server serve -d solana.solfunmeme.com -p 18090";
        Restart = "always"; RestartSec = "5";
        StandardOutput = "journal"; StandardError = "journal";
        NoNewPrivileges = true; PrivateTmp = true;
      };
      environment = { DASL_TESTING_ROOT = DASL_TESTING; };
    };

    # ═══════════════════════════════════════════════════════════
    # Tier 3: DAG-CBOR Harness Tiles (Rust prebuilt)
    # ═══════════════════════════════════════════════════════════
    systemd.services.serde-ipld-dagcbor-tile = {
      enable = true;
      description = "serde_ipld_dagcbor — Rust DAG-CBOR decoder tile";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple"; User = "dasl"; Group = "dasl";
        ExecStart = "${SERDE}/bin/service 18007";
        Restart = "always"; RestartSec = "5";
        StandardOutput = "journal"; StandardError = "journal";
        NoNewPrivileges = true; PrivateTmp = true; PrivateDevices = true;
        ProtectHome = "read-only"; ProtectSystem = "strict";
      };
      environment = { DASL_TESTING_ROOT = DASL_TESTING; };
    };

    systemd.services.n0-dasl-tile = {
      enable = true;
      description = "n0_dasl — Rust DAG-CBOR decoder tile";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple"; User = "dasl"; Group = "dasl";
        ExecStart = "${N0}/bin/service 18009";
        Restart = "always"; RestartSec = "5";
        StandardOutput = "journal"; StandardError = "journal";
        NoNewPrivileges = true; PrivateTmp = true; PrivateDevices = true;
        ProtectHome = "read-only"; ProtectSystem = "strict";
      };
      environment = { DASL_TESTING_ROOT = DASL_TESTING; };
    };

    systemd.services.libipld-tile = {
      enable = true;
      description = "libipld — Rust DAG-CBOR decoder tile";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple"; User = "dasl"; Group = "dasl";
        ExecStart = "${LIBIPLD}/bin/service 18011";
        Restart = "always"; RestartSec = "5";
        StandardOutput = "journal"; StandardError = "journal";
        NoNewPrivileges = true; PrivateTmp = true; PrivateDevices = true;
        ProtectHome = "read-only"; ProtectSystem = "strict";
      };
      environment = { DASL_TESTING_ROOT = DASL_TESTING; };
    };

    systemd.services.qa-team-tile = {
      enable = true;
      description = "QA Team Tile — cross-impl QA dashboard";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple"; User = "dasl"; Group = "dasl";
        ExecStart = "${QA}/bin/service 18142";
        Restart = "always"; RestartSec = "5";
        StandardOutput = "journal"; StandardError = "journal";
        NoNewPrivileges = true; PrivateTmp = true; PrivateDevices = true;
        ProtectHome = "read-only"; ProtectSystem = "strict";
      };
      environment = { DASL_TESTING_ROOT = DASL_TESTING; };
    };

    systemd.services.fuzzing-team-tile = {
      enable = true;
      description = "Fuzzing Team Tile — fuzz coverage dashboard";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple"; User = "dasl"; Group = "dasl";
        ExecStart = "${FUZZ}/bin/service 18143";
        Restart = "always"; RestartSec = "5";
        StandardOutput = "journal"; StandardError = "journal";
        NoNewPrivileges = true; PrivateTmp = true; PrivateDevices = true;
        ProtectHome = "read-only"; ProtectSystem = "strict";
      };
      environment = { DASL_TESTING_ROOT = DASL_TESTING; };
    };

    # ═══════════════════════════════════════════════════════════
    # Tier 4: Specialized Tiles
    # ═══════════════════════════════════════════════════════════
    systemd.services.diagonalize-tile = {
      enable = true;
      description = "Diagonalize Tile — plan GUI + blueprint diagnostics";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple"; User = "mdupont"; Group = "mdupont";
        ExecStart = "${pkgs.python3}/bin/python3 ${HOME}/dasl/ipld-car-ipc-shmem-linux/tasks/diagonalize/tile-server/server.py --port 8082";
        Restart = "always"; RestartSec = "5";
        NoNewPrivileges = true; PrivateTmp = true;
      };
      environment = { HOME = HOME; };
    };

    systemd.services.dasl-plan-tile = {
      enable = true;
      description = "DASL Plan Tile — GOAP planner dashboard";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple"; User = "mdupont"; Group = "mdupont";
        ExecStart = "${pkgs.python3}/bin/python3 ${HOME}/dasl-planning/scripts/dasl-plan-tile-server.py";
        Restart = "always"; RestartSec = "5";
        NoNewPrivileges = true; PrivateTmp = true;
      };
      environment = { HOME = HOME; };
    };

    systemd.services.zombie-cft-tile = {
      enable = true;
      description = "Zombie CFT Tile — Monster containment chamber";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple"; User = "zombie"; Group = "zombie";
        ExecStart = "/mnt/data1/time-2026/06-june/25/zombie-cft-tile/target/release/zombie-cft-tile -d solana.solfunmeme.com -p 8095";
        Restart = "always"; RestartSec = "5";
        StandardOutput = "journal"; StandardError = "journal";
        NoNewPrivileges = true; PrivateTmp = true;
      };
      environment = { HOME = HOME; };
    };

    # ═══════════════════════════════════════════════════════════
    # CID Indexers (disabled oneshots)
    # ═══════════════════════════════════════════════════════════
    systemd.services.cid-index-aristotle = {
      enable = false;
      description = "CID Index Aristotle Results → IPLD CAR";
      after = [ "local-fs.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "oneshot"; User = "dasl"; Group = "dasl";
        ExecStart = "${pkgs.python3}/bin/python3 ${HOME}/projects/lean-kg/declaration-cid.py ${HOME}/projects/arist/aristotles_results --output ${HOME}/projects/lean-kg/output-aristotle";
        StandardOutput = "journal"; StandardError = "journal";
        ProtectHome = "read-only"; NoNewPrivileges = true;
      };
    };

    systemd.services.cid-index-mathlib = {
      enable = false;
      description = "CID Index Mathlib-split → IPLD CAR";
      after = [ "local-fs.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "oneshot"; User = "dasl"; Group = "dasl";
        ExecStart = "${pkgs.python3}/bin/python3 ${HOME}/projects/lean-kg/declaration-cid.py ${HOME}/projects/lean-kg/mathlib-split --output ${HOME}/projects/lean-kg/output-mathlib";
        StandardOutput = "journal"; StandardError = "journal";
        ProtectHome = "read-only"; NoNewPrivileges = true;
      };
    };

    # ═══════════════════════════════════════════════════════════
    # SSL & Nginx
    # ═══════════════════════════════════════════════════════════
    systemd.services.nginx-log-setup = {
      enable = true;
      description = "Create nginx log directories and research error-docs archive";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "oneshot"; RemainAfterExit = true;
        User = "www-data"; Group = "www-data";
      };
      script = ''
        mkdir -p /var/log/nginx/error-docs
        touch /var/log/nginx/research.access.log /var/log/nginx/research.error.log
        chown www-data:www-data /var/log/nginx/research.access.log /var/log/nginx/research.error.log
        chmod 664 /var/log/nginx/research.access.log /var/log/nginx/research.error.log
      '';
    };

    systemd.services.ssl-selfsigned = {
      enable = true;
      description = "Ensure self-signed SSL fallback for ${domain}";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "oneshot"; RemainAfterExit = true;
        User = "root"; Group = "root";
      };
      script = let
        selfSignedCert = pkgs.runCommand "self-signed-cert" {} ''
          mkdir -p $out
          ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:2048 -keyout $out/key.pem -out $out/cert.pem -days 3650 -nodes -subj "/CN=${domain}" 2>/dev/null
        '';
      in ''
        leDir="/etc/letsencrypt/live/${domain}"
        leArchive="/etc/letsencrypt/archive/${domain}"
        mkdir -p "$leDir" "$leArchive" /etc/letsencrypt/accounts 2>/dev/null || true
        if [ ! -e "$leDir/fullchain.pem" ]; then
          ln -sf "${selfSignedCert}/cert.pem" "$leDir/cert.pem"
          ln -sf "${selfSignedCert}/key.pem" "$leDir/privkey.pem"
          ln -sf "${selfSignedCert}/cert.pem" "$leDir/fullchain.pem"
          ln -sf "${selfSignedCert}/cert.pem" "$leDir/chain.pem"
        fi
        chmod 755 /etc/letsencrypt/archive /etc/letsencrypt/archive/${domain} 2>/dev/null || true
        chmod 644 /etc/letsencrypt/archive/${domain}/*.pem 2>/dev/null || true
      '';
    };

    systemd.services.certbot-renew = {
      enable = true;
      description = "Renew Let's Encrypt SSL certificate for ${domain}";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.certbot}/bin/certbot renew --non-interactive";
      };
    };

    systemd.timers.certbot-renew = {
      enable = true;
      description = "Daily certbot renewal check for ${domain}";
      wants = [ "certbot-renew.service" ];
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily"; Persistent = true; RandomizedDelaySec = "3600";
      };
    };

    # ═══════════════════════════════════════════════════════════
    # Nginx — solana.solfunmeme.com (all routes)
    # ═══════════════════════════════════════════════════════════
    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      user = lib.mkForce "www-data";
      group = lib.mkForce "www-data";
      commonHttpConfig = ''
        client_body_buffer_size 1024k;
        map $status $is_error { ~^[23] 0; default 1; }
        log_format research '"$time_iso8601" client=$remote_addr method=$request_method uri=$request_uri status=$status body_bytes=$body_bytes_sent referer=$http_referer user_agent=$http_user_agent request_time=''${request_time}s upstream_addr=$upstream_addr upstream_status=$upstream_status scheme=$scheme host=$host';
        access_log /var/log/nginx/research.access.log research;
        error_log /var/log/nginx/research.error.log warn;
      '';
      virtualHosts."${domain}" = {
        forceSSL = true;
        sslCertificate = "/etc/letsencrypt/live/${domain}/fullchain.pem";
        sslCertificateKey = "/etc/letsencrypt/live/${domain}/privkey.pem";

        locations."/nora/" = { proxyPass = "http://127.0.0.1:4000/"; };
        locations."/nora/ci-results/" = {
          alias = "/mnt/data1/nora/ci-results/";
          extraConfig = ''autoindex on; add_header Cache-Control "no-store";'';
        };
        locations."/nora/health" = { proxyPass = "http://127.0.0.1:4000/health"; };
        locations."/pastebin/" = {
          proxyPass = "http://127.0.0.1:8090/";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            client_max_body_size 0;
            proxy_read_timeout 3600s; proxy_send_timeout 3600s; proxy_connect_timeout 3600s;
            proxy_buffering off; proxy_request_buffering off;
            charset utf-8;
          '';
        };
        locations."/block/" = {
          proxyPass = "http://127.0.0.1:8156/";
          extraConfig = ''add_header Access-Control-Allow-Origin "*"; client_max_body_size 10M;'';
        };
        locations."/lean4/" = {
          proxyPass = "http://127.0.0.1:8155/";
          extraConfig = ''add_header Access-Control-Allow-Origin "*"; client_max_body_size 10M;'';
        };
        locations."/tile/nagios/" = { proxyPass = "http://127.0.0.1:8800/"; extraConfig = ''add_header Access-Control-Allow-Origin "*";''; };
        locations."/tile/deploy/" = { proxyPass = "http://127.0.0.1:8810/"; extraConfig = ''add_header Access-Control-Allow-Origin "*"; proxy_read_timeout 120s;''; };
        locations."/tile/vendormod/" = { proxyPass = "http://127.0.0.1:8765/"; extraConfig = ''add_header Access-Control-Allow-Origin "*";''; };
        locations."/tile/port-registry/" = { proxyPass = "http://127.0.0.1:8820/"; extraConfig = ''add_header Access-Control-Allow-Origin "*";''; };
        locations."/tile/serde-dagcbor/" = { proxyPass = "http://127.0.0.1:18007/"; extraConfig = ''add_header Access-Control-Allow-Origin "*";''; };
        locations."/tile/n0-dasl/" = { proxyPass = "http://127.0.0.1:18009/"; extraConfig = ''add_header Access-Control-Allow-Origin "*";''; };
        locations."/tile/libipld/" = { proxyPass = "http://127.0.0.1:18011/"; extraConfig = ''add_header Access-Control-Allow-Origin "*";''; };
        locations."/tile/qa/" = { proxyPass = "http://127.0.0.1:18142/"; extraConfig = ''add_header Access-Control-Allow-Origin "*";''; };
        locations."/tile/fuzz/" = { proxyPass = "http://127.0.0.1:18143/"; extraConfig = ''add_header Access-Control-Allow-Origin "*";''; };
        locations."/tile/coverage/" = { proxyPass = "http://127.0.0.1:18150/"; extraConfig = ''add_header Access-Control-Allow-Origin "*";''; };
        locations."/tile/goap/" = { proxyPass = "http://127.0.0.1:8842/"; extraConfig = ''add_header Access-Control-Allow-Origin "*";''; };
        locations."/tile/plan/" = { proxyPass = "http://127.0.0.1:8888/"; extraConfig = ''add_header Access-Control-Allow-Origin "*";''; };
        locations."/tile/diagonalize/" = { proxyPass = "http://127.0.0.1:8082/"; extraConfig = ''add_header Access-Control-Allow-Origin "*";''; };
        locations."/tile/zombie/" = { proxyPass = "http://127.0.0.1:8095/"; extraConfig = ''add_header Access-Control-Allow-Origin "*";''; };
        locations."/task-runner/" = {
          proxyPass = "http://127.0.0.1:18099/tiles/task-runner-schedule/";
          extraConfig = ''add_header Access-Control-Allow-Origin "*"; proxy_read_timeout 120s; proxy_send_timeout 120s;'';
        };
        locations."/notebooklm/" = {
          alias = "/var/www/${domain}/notebooklm/";
          extraConfig = ''autoindex on; autoindex_exact_size off; charset utf-8; add_header Cache-Control "no-cache, must-revalidate, max-age=0"; expires -1;'';
        };
        locations."/nginx-docs/errors/" = {
          alias = "/var/log/nginx/error-docs/";
          extraConfig = ''autoindex on; autoindex_exact_size off; autoindex_localtime on; default_type text/markdown;'';
        };
      };
    };

    systemd.services.nginx = {
      serviceConfig = { User = "www-data"; Group = "www-data"; };
    };

    environment.systemPackages = with pkgs; [ curl jq nginx openssl certbot ];
  };
}
