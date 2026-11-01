# One unit for the agent fabric.
#
# Every piece this needs was already on the host and none of them knew about
# each other: the pastebin on :8090 with its git mounts and IPFS blocks, the
# Kant relay on :8787 that carries chat lines, the IPLD CAR shmem pools on
# :8150/:8154, Postgres, Kubo on :8081, the GPU, and a Cloudflare Durable
# Object board that until now was only reachable by hand from a terminal.
#
# `kant-fabric` is the daemon that owns them together:
#
#   * a task is a row in Postgres, and every change to it is an event whose
#     `block_cid` is the address of the event's own canonical bytes. The bytes
#     go to Kubo, the line goes to a relay room, and anyone who receives it —
#     a second native agent, the wasm peer, or the Durable Object — recomputes
#     the address and drops the line if it disagrees. A relay or a Worker
#     therefore cannot invent or edit an event;
#   * chat between agents is the same log on the same rooms, so it inherits
#     the same check. The relay only ever carries lines, it never parses them;
#   * the Durable Object is a mirror, never the source of truth. Local work
#     does not wait on Cloudflare; a fresh host can rebuild every task from the
#     object (that is the "local one" and the DO sync being the same path).
#
# What is *not* here, stated plainly so nobody assumes otherwise:
#
#   * the daemon does not run anything on the GPU. The gate reports the
#     devices (and `agent-fabric capabilities` exposes them), so an agent can
#     decide where to run its own work; nothing is scheduled by this unit.
#   * the shmem pools are read through their own HTTP health, not written to:
#     block storage is Kubo, and the pools stay the shared-memory view that
#     other tools already use.
#
# `ExecStartPre = gate` is the point of the whole file. The unit does not come
# up unless Postgres, the pastebin, the relay, the tasks pool, the Cloudflare
# API, `ipfs version` and the letta pool all answer; the journal keeps the
# report either way. "Running" then means "wired", not "started and hoping".
{ config, lib, pkgs, pastebin-src, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  fabric = pastebin-src.packages.${system}.agent-fabric;

  port = 8190;
  socket = "/run/agent-fabric/fabric.sock";
  doPort = 18791;

  # Writable copy of the Worker. The flake's store path is read-only and
  # wrangler wants to write beside its config even with --persist-to.
  doRoot = "/var/lib/agent-fabric";

  # The two git checkouts the fabric may hand out files from, the same shape
  # the pastebin's git_mount module understands.
  gitMounts = [ "/mnt/data1/kant/pastebin" "/mnt/data1/twitterstorm" ];

  # Everything below is deployed by other modules on this host. `wants` rather
  # than `requires`: a unit that is temporarily missing must not make the
  # fabric unstartable, and the gate is what enforces readiness anyway.
  dependencies = [
    "postgresql.service"
    "ipld-car-shmem-tasks.service"
    "kant-pastebin.service"
    "kant-zk-relay.service"
  ];

  # nixpkgs calls Kubo `kubo`; the fallback keeps this evaluable on an older
  # pin where the attribute was still `ipfs`.
  kubo = pkgs.kubo or pkgs.ipfs;

  # wrangler comes from nixpkgs when it is there. When it is not, the host's
  # own system-manager profile has one (that is where /run/system-manager/sw
  # comes from), and failing that the ExecStop-less restart loop will say so in
  # the journal rather than taking the daemon down with it.
  wranglerBin =
    if pkgs ? wrangler then "${pkgs.wrangler}/bin/wrangler"
    else "/run/system-manager/sw/bin/wrangler";
in
{
  # ═══════════════════════════════════════════════════════════
  # Writable state
  # ═══════════════════════════════════════════════════════════
  systemd.tmpfiles.rules = [
    "d /run/agent-fabric 0750 kant kant -"
    "d ${doRoot} 0750 kant kant -"
    "d ${doRoot}/src 0750 kant kant -"
    "d ${doRoot}/durable 0750 kant kant -"
  ];

  # ═══════════════════════════════════════════════════════════
  # The Durable Object board, run locally (:18791)
  #
  # This is the same worker that `wrangler deploy` puts in Cloudflare; running
  # it under workerd here means the sync path is exercised on every boot
  # instead of only when someone remembers to deploy.
  # ═══════════════════════════════════════════════════════════
  systemd.services.kant-fabric-do = {
    enable = true;
    description = "Agent fabric — Cloudflare Durable Object board (local workerd mirror)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = [ pkgs.nodejs pkgs.git ];
    environment = {
      HOME = "/srv/kant";
      CI = "1";
      DO_NOT_TRACK = "1";
      WRANGLER_SEND_METRICS = "false";
      # A local object needs no account; wrangler only insists that the
      # variable exists when one of the commands reaches for it.
      CLOUDFLARE_API_TOKEN = "";
      CLOUDFLARE_ACCOUNT_ID = "";
    };
    serviceConfig = {
      Type = "simple";
      User = "kant";
      Group = "kant";
      WorkingDirectory = "${doRoot}/src";
      ExecStartPre = [
        "${pkgs.coreutils}/bin/install -m 0644 ${pastebin-src}/fabric/durable/worker.mjs ${doRoot}/src/worker.mjs"
        "${pkgs.coreutils}/bin/install -m 0644 ${pastebin-src}/fabric/durable/wrangler.toml ${doRoot}/src/wrangler.toml"
      ];
      ExecStart = "${wranglerBin} dev --ip 127.0.0.1 --port ${toString doPort} --local --persist-to ${doRoot}/durable";
      Restart = "always";
      RestartSec = "10";
      # A worker that cannot bind its port yet is a restart, not a failure of
      # the boot; the fabric's gate treats the board as optional.
      StartLimitIntervalSec = 0;
      StandardOutput = "journal";
      StandardError = "journal";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "full";
      ProtectHome = false;
      ReadWritePaths = [ doRoot "/srv/kant" ];
    };
  };

  # ═══════════════════════════════════════════════════════════
  # The fabric itself (:8190 + unix socket)
  # ═══════════════════════════════════════════════════════════
  systemd.services.kant-fabric = {
    enable = true;
    description = "Agent fabric — tasks, chat and content-addressed blocks across agents";
    wantedBy = [ "multi-user.target" ];
    wants = dependencies;
    after = dependencies ++ [ "kant-fabric-do.service" "network.target" ];
    # `psql` is how the store talks to postgres (see src/bin/fabric/store.rs:
    # every value is passed as a psql variable, never pasted into SQL), `ipfs`
    # is how a block is written, and `letta-ipld-memory` is the pool the gate
    # pings. Declared here rather than inherited from a login shell: a unit
    # that only works because of a user's PATH is not a unit.
    #
    # The profile suffix is not laziness. `letta-ipld-memory` ships with
    # ipld-car-ipc-shmem-linux, which is not an input of this flake; the host's
    # system-manager profile is where that package actually lives
    # (/run/system-manager/sw/bin/letta-ipld-memory), so this is the one entry
    # that could not be pinned to a package here.
    # mkForce because the systemd module also defines PATH (from `path`, the
    # way it does for every unit); this is the deliberate override of that
    # default, not a second opinion about it.
    environment.PATH = lib.mkForce (lib.concatStringsSep ":" [
      (lib.makeBinPath [ kubo pkgs.git pkgs.postgresql ])
      "/run/system-manager/sw/bin"
    ]);
    environment.HOME = "/home/mdupont";
    environment = {
      FABRIC_DB = "agent_fabric";
      FABRIC_HTTP = "127.0.0.1:${toString port}";
      FABRIC_SOCKET = socket;
      FABRIC_LEASE_SECS = "120";
      FABRIC_TICK_SECS = "5";
      FABRIC_SYNC_SECS = "5";

      # Blocks: Kubo writes, the local gateway reads back.
      FABRIC_IPFS = "ipfs";
      FABRIC_IPFS_GATEWAY = "http://127.0.0.1:8081";
      FABRIC_POOL = "tasks";
      FABRIC_LETTA = "letta-ipld-memory";

      # The pieces that already existed and are now one system.
      FABRIC_PASTEBIN = "http://127.0.0.1:8090";
      FABRIC_RELAY = "http://127.0.0.1:8787";
      FABRIC_SHMEM = "http://127.0.0.1:8154";
      FABRIC_CF_API = "http://127.0.0.1:3323";
      FABRIC_DO_URL = "http://127.0.0.1:${toString doPort}/board";
      FABRIC_GIT_MOUNTS = lib.concatStringsSep ":" gitMounts;

      RUST_LOG = "info";
      PGCONNECT_TIMEOUT = "5";
    };
    serviceConfig = {
      Type = "simple";
      # Runs as the database role, not as the pastebin's `kant` user.
      # pg_hba's local rules are `peer`: the OS user *is* the database user, so
      # this unit needs either a role per service or the user that already owns
      # the fabric database. mdupont is that role, and it is also what owns the
      # two git mounts and the pastebin spool this daemon reads. Inventing a
      # `kant` role plus a password file would be a second credential to rotate
      # for no gain; the socket on /run/agent-fabric is what limits who can
      # reach the daemon.
      User = "mdupont";
      Group = "mdupont";
      RuntimeDirectory = "agent-fabric";
      RuntimeDirectoryMode = "0750";
      # Readiness gate. Non-zero exit here is a restart, and the report it
      # printed is the first thing to read in the journal.
      ExecStartPre = "${fabric}/bin/agent-fabric gate";
      ExecStart = "${fabric}/bin/agent-fabric serve";
      Restart = "always";
      RestartSec = "15";
      StartLimitIntervalSec = 0;
      TimeoutStartSec = "120";
      TimeoutStopSec = "30";
      StandardOutput = "journal";
      StandardError = "journal";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "full";
      ProtectHome = false;
      ReadWritePaths = [ "/run/agent-fabric" "/mnt/data1" "/srv/kant" ];
    };
  };
}
