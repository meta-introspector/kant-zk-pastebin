// server/scheduler.mjs — systemd-driven supervisor loop.
//
// This is what the systemd unit ExecStart points to. It:
//  1. Starts the thunk server (hosts thunks, runs them)
//  2. Runs a scheduling loop that ticks and executes due work
//  3. Eventually the server will install its own schedules and
//     this becomes a thin launcher.

import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { ThunkStore } from "./thunk-store.mjs";
import { Schedule } from "./schedule.mjs";
import { Server } from "./server.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "..");

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const storeDir = args["--store"] ?? resolve(ROOT, "state", "thunks");
  const port = Number(args["--port"] ?? 8787);
  const interval = Number(args["--interval"] ?? 5000);

  console.log(`[scheduler] starting: store=${storeDir} port=${port} interval=${interval}ms`);

  const thunkStore = new ThunkStore(storeDir);
  const schedule = new Schedule();
  const server = new Server({ thunkStore, schedule, port });

  await server.start();
  console.log(`[scheduler] server listening on :${port}`);

  // Load any schedule manifest from disk to seed the scheduler
  const manifestPath = resolve(ROOT, "state", "schedule.json");
  try {
    const { readFileSync } = await import("node:fs");
    const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
    schedule.installManifest(manifest);
    console.log(`[scheduler] installed ${manifest.length} schedule entries`);
  } catch { /* no manifest yet */ }

  // Main loop — systemd drives this
  const loop = setInterval(() => {
    const now = Date.now();
    const work = schedule.tick(now);
    if (work.length) schedule.runAll({ server, thunkStore }).catch((e) => console.error("[scheduler] runAll", e));
  }, interval);

  process.on("SIGINT", () => { clearInterval(loop); server.stop(); process.exit(0); });
  process.on("SIGTERM", () => { clearInterval(loop); server.stop(); process.exit(0); });

  console.log("[scheduler] running — systemd is the scheduler");
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const key = a;
      const val = argv[i + 1]?.startsWith("--") ? true : argv[++i];
      out[key] = val ?? true;
    }
  }
  return out;
}

main().catch((e) => { console.error("[scheduler] fatal", e); process.exit(1); });