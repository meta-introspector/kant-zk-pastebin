{ config, lib, pkgs, pastebin-src, nora-src, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  HOME = "/home/mdupont";
  DOCS = "${HOME}/DOCS";
  domain = "solana.solfunmeme.com";
  kant-pastebin = pastebin-src.packages.${system}.kant-pastebin;
  nora = nora-src.packages.${system}.default;
  daslTilesRust = "/nix/store/syy7kivh3sfprsbmsqxyxhad1a1j1rx8-dasl-tiles-rust-0.1.0";
  DASL_TESTING = "${HOME}/dasl/dasl-testing";
  # Harness binaries — built from ~/dasl/dasl-testing/harnesses/ (cargo build --release)
  SERDE   = "${DASL_TESTING}/harnesses/serde_ipld_dagcbor/target/release";
  N0      = "${DASL_TESTING}/harnesses/n0_dasl/target/release";
  LIBIPLD = "${DASL_TESTING}/harnesses/libipld/target/release";
  QA      = "${DASL_TESTING}/harnesses/qa-team-tile/target/release";
  FUZZ    = "${DASL_TESTING}/harnesses/fuzz-team-tile/target/release";
  ZOMBIE  = "/mnt/data1/nix/vendor/rust/cargo2nix/submodules/rust-build/compiler/zombie_driver2/target/debug";
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
        ExecStart = "${pkgs.bash}/bin/bash /mnt/data1/kant/pastebin/scripts/svg2anim-worker.sh";
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
        ExecStart = "${SERDE}/service 18007";
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
        ExecStart = "${N0}/service 18009";
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
        ExecStart = "${LIBIPLD}/service 18011";
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
        ExecStart = "${QA}/qa-team-tile 18142";
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
        ExecStart = "${FUZZ}/fuzz-team-tile 18143";
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
        ExecStart = "${pkgs.python3}/bin/python3 ${HOME}/dasl-planning/tile-servers/goap-planner-tile-server.py --port 8888";
        Restart = "always"; RestartSec = "5";
        NoNewPrivileges = true; PrivateTmp = true;
      };
      environment = { HOME = HOME; };
    };

    # ─── GOAP Planner Tile (:8842) ─────────────────────────
    systemd.services.goap-planner-tile = {
      enable = true;
      description = "GOAP Planner Tile — A* plan + sheaf scanner dashboard";
      after = [ "network.target" ];
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "simple"; User = "mdupont"; Group = "mdupont";
        ExecStart = "${pkgs.python3}/bin/python3 ${HOME}/dasl-planning/tile-servers/goap-planner-tile-server.py --port 8842";
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
        ExecStart = "${ZOMBIE}/zombie-cft-tile --port 8095";
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
        User = "root"; Group = "root";
      };
      script = ''
        mkdir -p /var/log/nginx/error-docs
        chown www-data:www-data /var/log/nginx/error-docs
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

        # Aristotle Projects — 59 static sites at /arist/
        locations."/arist/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/49cde238-502e-46e8-933a-29085ac44cd7/output-final_aristotle/arist-index-out/";
          extraConfig = ''index index.html; try_files $uri $uri/ /arist/index.html; add_header Cache-Control "public, max-age=300";'';
        };

        locations."/arist/bc7b9363-c4ec-46be-b980-4d6754b47369/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/bc7b9363-c4ec-46be-b980-4d6754b47369/output-final_aristotle/www/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/8c581d03-4852-4bef-97f2-52da8b6ddd9c/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/8c581d03-4852-4bef-97f2-52da8b6ddd9c/output-final_aristotle/web/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/ff756caf-8d26-4f8c-af96-981be215a038/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/ff756caf-8d26-4f8c-af96-981be215a038/output-final_aristotle/web/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/320e10ec-82df-413a-8095-40696936945c/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/320e10ec-82df-413a-8095-40696936945c/output-final_aristotle/site/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/49cde238-502e-46e8-933a-29085ac44cd7/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/49cde238-502e-46e8-933a-29085ac44cd7/output-final_aristotle/dist/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/d79d4cfd-1c60-40fc-ae16-bb0498953ec1/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/d79d4cfd-1c60-40fc-ae16-bb0498953ec1/output-final_aristotle/web/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/9de417cd-c219-4a95-87df-28bce8e54282/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/9de417cd-c219-4a95-87df-28bce8e54282/output-final_aristotle/zkpop-lab/web/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/8ca0886c-8b67-49af-9cf7-7a87432ae2ef/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/8ca0886c-8b67-49af-9cf7-7a87432ae2ef/output-final_aristotle/web/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/8466c852-2184-4971-b3d9-8387832725d6/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/8466c852-2184-4971-b3d9-8387832725d6/output-final_aristotle/site/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/6f91c03d-87e8-4c6a-8d3f-de39edee2f6d/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/6f91c03d-87e8-4c6a-8d3f-de39edee2f6d/output-final_aristotle/web/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/45f2b7a7-9f63-41cb-a1a9-2e7148fcc790/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/45f2b7a7-9f63-41cb-a1a9-2e7148fcc790/output-final_aristotle/site/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/e848cef2-9456-407a-880c-650aee38cf3d/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/e848cef2-9456-407a-880c-650aee38cf3d/output-final_aristotle/web/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/7cf3d70a-7e0a-4b69-a15e-efb3f5f91b47/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/7cf3d70a-7e0a-4b69-a15e-efb3f5f91b47/output-final_aristotle/web/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/6eef2143-29e7-4daf-a720-88e8b2f10558/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/6eef2143-29e7-4daf-a720-88e8b2f10558/app/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/c481ea66-720e-4de4-a23e-534ebe3bc249/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/c481ea66-720e-4de4-a23e-534ebe3bc249/output-final_aristotle/dist/site/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/97b722f5-7ccb-464b-a2ee-6990deb0ab46/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/97b722f5-7ccb-464b-a2ee-6990deb0ab46/output-final_aristotle/site/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/70faa4e4-6997-4577-8f8b-19157a44d1f4/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/70faa4e4-6997-4577-8f8b-19157a44d1f4/output-final_aristotle/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/1df7337a-6cf3-4369-9947-f6cd72758391/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/1df7337a-6cf3-4369-9947-f6cd72758391/output-final_aristotle/dist/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/026c4360-d325-4310-915c-65ed42cb51fa/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/026c4360-d325-4310-915c-65ed42cb51fa/output-final_aristotle/web/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/f9c6ef16-7a30-42a3-ae51-61cc4b026ef7/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/f9c6ef16-7a30-42a3-ae51-61cc4b026ef7/output-final_aristotle/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/f4bbd347-082b-4823-9d8b-d3fd9cdbc49f/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/f4bbd347-082b-4823-9d8b-d3fd9cdbc49f/output-final_aristotle/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/f070c0af-1098-4492-911d-5735d260182b/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/f070c0af-1098-4492-911d-5735d260182b/output-final_aristotle/web/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/e73737f7-0910-4c54-8f5f-d95563875485/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/e73737f7-0910-4c54-8f5f-d95563875485/output-final_aristotle/memes/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/e65146c2-d9c3-4bd9-a0b8-ce857269773d/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/e65146c2-d9c3-4bd9-a0b8-ce857269773d/output-final_aristotle/introspection/proofs/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/e6379ff2-df8e-456c-bbcb-241fb7c95ead/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/e6379ff2-df8e-456c-bbcb-241fb7c95ead/output-final_aristotle/visualization/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/d46acc4d-8232-479c-a023-86f6756f07ec/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/d46acc4d-8232-479c-a023-86f6756f07ec/output-final_aristotle/introspection/proofs/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/cd2db6d7-f436-49c2-8803-396b012f73c2/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/cd2db6d7-f436-49c2-8803-396b012f73c2/output-final_aristotle/svg/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/c84b6626-94b3-45cc-a391-a418c9f0206f/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/c84b6626-94b3-45cc-a391-a418c9f0206f/output-final_aristotle/visuals/automata/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/c6f9217b-ca94-4d5c-852c-d2f12c902d0d/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/c6f9217b-ca94-4d5c-852c-d2f12c902d0d/output-final_aristotle/qr/codes/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/bd5015af-2624-42c6-83c4-b171a31159c5/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/bd5015af-2624-42c6-83c4-b171a31159c5/output-final_aristotle/introspection/proofs/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/ae06ae06-2580-422a-8fc3-92aeaaca8762/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/ae06ae06-2580-422a-8fc3-92aeaaca8762/output-final_aristotle/site/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/9cbef93a-b178-4e37-ad8b-d0015f5c6320/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/9cbef93a-b178-4e37-ad8b-d0015f5c6320/output-final_aristotle/site/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/95d6eee6-ec00-4ea7-814d-36b308d3ac94/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/95d6eee6-ec00-4ea7-814d-36b308d3ac94/output-final_aristotle/introspection/proofs/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/932247ec-4b02-4568-a780-871ffcb5e6cf/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/932247ec-4b02-4568-a780-871ffcb5e6cf/output-final_aristotle/data/dasl-test-case-feed/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/7daee212-7ae4-492b-a5bc-24c16905ec20/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/7daee212-7ae4-492b-a5bc-24c16905ec20/output-final_aristotle/introspection/proofs/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/7b8ed53e-3e05-436e-b2b5-6f4ea15dc081/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/7b8ed53e-3e05-436e-b2b5-6f4ea15dc081/output-final_aristotle/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/78bd0170-4edb-458b-8923-e263f1d6eea0/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/78bd0170-4edb-458b-8923-e263f1d6eea0/output-final_aristotle/WorkPlan/site/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/74949b46-5475-419e-b2ee-95272da2d8ea/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/74949b46-5475-419e-b2ee-95272da2d8ea/output-final_aristotle/proofs/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/63c53cf9-0c46-44f3-a1f4-3f5eb5028979/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/63c53cf9-0c46-44f3-a1f4-3f5eb5028979/output-final_aristotle/output/visualization/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/5fa470ab-7a00-4ba8-b7d5-b285fffa00ca/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/5fa470ab-7a00-4ba8-b7d5-b285fffa00ca/output-final_aristotle/render/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/5e8b853a-1adc-404c-a762-f694d2c8a4cf/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/5e8b853a-1adc-404c-a762-f694d2c8a4cf/output-final_aristotle/web/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/583e94a2-ca13-4765-ab0c-c1cef5e859dc/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/583e94a2-ca13-4765-ab0c-c1cef5e859dc/output-final_aristotle/figures/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/437f421b-b4a4-487f-b11f-e4a856871901/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/437f421b-b4a4-487f-b11f-e4a856871901/output-final_aristotle/gallery/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/432c5102-a632-421f-bef9-ff66365d59eb/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/432c5102-a632-421f-bef9-ff66365d59eb/output-final_aristotle/site/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/314d2678-04ac-4fe6-81b9-79823409bef1/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/314d2678-04ac-4fe6-81b9-79823409bef1/output-final_aristotle/svg/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/30c0ca50-8b8f-44d7-9fca-5de74cb658be/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/30c0ca50-8b8f-44d7-9fca-5de74cb658be/output-final_aristotle/webapp/static/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/20ce677d-de2f-498b-9f6a-8f84d57375f2/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/20ce677d-de2f-498b-9f6a-8f84d57375f2/output-final_aristotle/web/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/18cc3cb5-1942-4d3e-b81b-241d311fa0d2/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/18cc3cb5-1942-4d3e-b81b-241d311fa0d2/output-final_aristotle/introspection/proofs/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/17b38b65-9e5a-4c0e-9184-307b5e00f639/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/17b38b65-9e5a-4c0e-9184-307b5e00f639/output-final_aristotle/gallery/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/10d30754-b3cc-4dac-8033-04ee31afacaa/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/10d30754-b3cc-4dac-8033-04ee31afacaa/output-final_aristotle/comic/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/0e9b52e1-f15d-4825-ade2-faaf2c7c4c22/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/0e9b52e1-f15d-4825-ade2-faaf2c7c4c22/output-final_aristotle/walkthrough/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/0c05e4e5-1c87-41bd-9eb3-86eb7aaf7a5e/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/0c05e4e5-1c87-41bd-9eb3-86eb7aaf7a5e/output-final_aristotle/introspection/proofs/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/0367857d-f1a0-4775-a81a-9eca140fbf67/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/0367857d-f1a0-4775-a81a-9eca140fbf67/output-final_aristotle/upstream/zoo/medium/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/01cf5ff3-cc71-4aef-8b74-1644d23da7de/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/01cf5ff3-cc71-4aef-8b74-1644d23da7de/output-final_aristotle/site/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/01611b1b-20e1-40ac-8da1-7ea508d9520c/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/01611b1b-20e1-40ac-8da1-7ea508d9520c/output-final_aristotle/introspection/proofs/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/eaa8dca6-ba2d-4919-be7c-3a1ff87483d7/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/eaa8dca6-ba2d-4919-be7c-3a1ff87483d7/output-final_aristotle/viz/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/519820ae-c978-4b6f-8856-9abd2aeb3c8d/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/519820ae-c978-4b6f-8856-9abd2aeb3c8d/output-final_aristotle/spirograph_infographics/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/b0e2bcbe-cbaa-4af4-b6c3-fdc7ca8ea8a4/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/b0e2bcbe-cbaa-4af4-b6c3-fdc7ca8ea8a4/output-final_aristotle/out/mathlib/ngrams/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
        };
        locations."/arist/25ed1bd0-03e5-404a-8af0-7348190495c8/" = {
          alias = "/mnt/data1/time-2026/05-may/07/arist/25ed1bd0-03e5-404a-8af0-7348190495c8/output-final_aristotle/web/";
          extraConfig = ''index index.html; try_files $uri $uri/ =404; add_header Cache-Control "public, max-age=3600";'';
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
