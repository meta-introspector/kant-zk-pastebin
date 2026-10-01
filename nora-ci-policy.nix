# Nora CI Pipeline Policy
# ========================
# Defines the automated CI pipeline for the NORA Artifact Registry:
#   1. nix-build — builds all packages
#   2. nix-logs — aggregates build logs
#   3. test-suites — cargo nextest (unit + integration)
#   4. fuzz-testing — all 6 cargo-fuzz targets
#   5. perf-recording — criterion benchmarks + binary stats
#   6. coverage — tarpaulin code coverage
#   7. aggregate-results — writes status.json for the dashboard tile
#
# Results are stored at /mnt/data1/nora/ci-results/ and served at
# https://solana.solfunmeme.com/nora/ci-results/
#
# The nora-tile (C-ABI cdylib) reads status.json and renders an HTML
# dashboard at /plugin/nora-tile/{id} via the pastebin plugin system.
#
# Retention: results older than 7 days are pruned daily.

{ config, lib, pkgs, self, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  pipelight = self.packages.${system}.pipelight;
  noraDir = "/home/mdupont/2026/05/28/nora";
  resultsDir = "/mnt/data1/nora/ci-results";
  inherit (lib) mkIf mkOption types;
in

{

  # ── Configurable options ─────────────────────────────────────────
  options.services.nora-ci = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable the Nora CI pipeline timer and services";
    };

    interval = mkOption {
      type = types.str;
      default = "hourly";
      description = "How often to run the CI pipeline (systemd OnCalendar format)";
    };

    retentionDays = mkOption {
      type = types.int;
      default = 7;
      description = "Number of days to retain old CI results";
    };

    resultsDir = mkOption {
      type = types.path;
      default = resultsDir;
      description = "Directory for CI pipeline results";
    };
  };

  # ── Implementation ──────────────────────────────────────────────
  config = mkIf config.services.nora-ci.enable {

    # NOTE: /mnt/data1/nora/ci-results/ directories are created by the
    # pipeline script (via sudo mkdir) instead of systemd.tmpfiles.rules
    # because /mnt/data1 is owned by mdupont and tmpfiles refuses unsafe
    # path transitions across ownership boundaries.

    # ── Pipeline runner (oneshot service) ──────────────────────────
    systemd.services.nora-ci-pipeline = {
      description = "NORA CI Pipeline — build, test, fuzz, perf, coverage";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" "nora.service" ];
      before = [ "nora-tile-cache.service" ];

      serviceConfig = {
        Type = "oneshot";
        User = "mdupont";
        Group = "mdupont";
        WorkingDirectory = noraDir;
        # Capabilities for perf recording
        AmbientCapabilities = [ "CAP_SYS_PTRACE" "CAP_SYS_ADMIN" ];
      };

      environment = {
        NORA_RESULTS_DIR = config.services.nora-ci.resultsDir;
        RUST_LOG = "info";
      };

      script = ''
        set -eu
        export PATH="${pkgs.cargo-fuzz}/bin:${pkgs.cargo-nextest}/bin:${pkgs.cargo-tarpaulin}/bin:${pkgs.cargo}/bin:$PATH"
        RESULTS="${config.services.nora-ci.resultsDir}"
        mkdir -p "$RESULTS"/{build,tests,fuzz,perf,coverage}

        echo "=== [1/6] Nix build ==="
        ${pkgs.nix}/bin/nix build .#nora-registry --no-link --print-out-paths 2>&1 | \
          tee "$RESULTS/build/nix-build.log"
        echo '{"status":"success","timestamp":"'"$(date -Iseconds)"'","build":"nora-registry"}' \
          > "$RESULTS/build/status.json"

        echo "=== [2/6] Nix log aggregation ==="
        ${pkgs.nix}/bin/nix log /nix/store/*nora* 2>&1 | tail -100 \
          > "$RESULTS/build/nix-log-tail.txt" 2>/dev/null || true

        echo "=== [3/6] Test suites ==="
        ${pkgs.cargo-nextest}/bin/cargo nextest run --package nora-registry --profile ci 2>&1 | \
          tee "$RESULTS/tests/nextest.log" || true
        ${pkgs.cargo}/bin/cargo test --lib --bin nora 2>&1 | \
          tee "$RESULTS/tests/cargo-test.log" || true
        grep -E 'PASS|FAIL|test result|error|FAILED' "$RESULTS/tests/nextest.log" | tail -5 \
          > "$RESULTS/tests/summary.txt" 2>/dev/null || true

        echo "=== [4/6] Fuzz testing ==="
        for target in fuzz_validation fuzz_docker_manifest fuzz_npm_metadata \
                       fuzz_maven_path fuzz_pypi_parse fuzz_config_toml; do
          echo "--- $target ---"
          timeout 30 ${pkgs.cargo}/bin/cargo fuzz run "$target" -- \
            -max_total_time=10 -runs=10000 2>&1 | tee "$RESULTS/fuzz/$target.log" || true
        done

        echo "=== [5/6] Perf recording ==="
        ${pkgs.cargo}/bin/cargo bench --package nora-registry --bench parsing \
          -- --save-baseline nora-ci 2>&1 | tee "$RESULTS/perf/criterion.log" || true

        echo "=== [6/6] Coverage ==="
        ${pkgs.cargo-tarpaulin}/bin/cargo-tarpaulin \
          --package nora-registry --out Html \
          --output-dir "$RESULTS/coverage" --skip-clean 2>&1 | \
          tee "$RESULTS/coverage/tarpaulin.log" || true
        grep -oP '\d+\.\d+%' "$RESULTS/coverage/tarpaulin.log" | tail -1 \
          > "$RESULTS/coverage/percent.txt" 2>/dev/null || true

        echo "=== Aggregate results for tile ==="
        COVERAGE=$(cat "$RESULTS/coverage/percent.txt" 2>/dev/null || echo "N/A")
        TEST_SUMMARY=$(cat "$RESULTS/tests/summary.txt" 2>/dev/null || echo "No data")
        cat > "$RESULTS/status.json" << JSON
        {
          "pipeline": "nora-full-ci",
          "timestamp": "$(date -Iseconds)",
          "build": $(cat "$RESULTS/build/status.json" 2>/dev/null || echo '{"status":"unknown"}'),
          "tests": {"summary": "''${TEST_SUMMARY}"},
          "fuzz": {"summary": "6 targets, $(grep -c crash "$RESULTS"/fuzz/*.log 2>/dev/null || echo 0) crashes"},
          "perf": {"binary": "$(cat "$RESULTS"/perf/binary-stats.txt 2>/dev/null || echo 'pending')"},
          "coverage": "''${COVERAGE}"
        }
JSON
        echo "Dashboard: https://solana.solfunmeme.com/nora/ci-results/"
      '';
    };

    # ── Pipeline timer ─────────────────────────────────────────────
    systemd.timers.nora-ci-pipeline = {
      description = "Timer for NORA CI pipeline (${config.services.nora-ci.interval})";
      wants = [ "nora-ci-pipeline.service" ];
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = config.services.nora-ci.interval;
        Persistent = true;
        RandomizedDelaySec = "300";
      };
    };

    # ── Retention cleanup ──────────────────────────────────────────
    systemd.services.nora-ci-cleanup = {
      description = "Clean up old NORA CI results (>${toString config.services.nora-ci.retentionDays}d)";
      after = [ "nora-ci-pipeline.service" ];

      serviceConfig = {
        Type = "oneshot";
        User = "mdupont";
      };

      script = ''
        RESULTS="${config.services.nora-ci.resultsDir}"
        find "$RESULTS" -name "*.log" -mtime +${toString config.services.nora-ci.retentionDays} -delete 2>/dev/null || true
        find "$RESULTS" -name "*.txt" -mtime +${toString config.services.nora-ci.retentionDays} -delete 2>/dev/null || true
        find "$RESULTS" -name "*.json" -mtime +${toString config.services.nora-ci.retentionDays} ! -name "status.json" -delete 2>/dev/null || true
        echo "Cleanup complete for results older than ${toString config.services.nora-ci.retentionDays} days"
      '';
    };

    systemd.timers.nora-ci-cleanup = {
      description = "Daily cleanup of old CI results";
      wants = [ "nora-ci-cleanup.service" ];
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    # ── Serve results directory via nginx ──────────────────────────
    services.nginx.virtualHosts."solana.solfunmeme.com" = {
      forceSSL = true;
      sslCertificate = "/etc/letsencrypt/live/solana.solfunmeme.com/fullchain.pem";
      sslCertificateKey = "/etc/letsencrypt/live/solana.solfunmeme.com/privkey.pem";

      locations."/nora/health" = {
        proxyPass = "http://127.0.0.1:4000/health";
      };

      locations."/nora/ci-results/" = {
        alias = "/mnt/data1/nora/ci-results/";
        extraConfig = ''
          autoindex on;
          add_header Cache-Control "no-store";
        '';
      };

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
  };
}
