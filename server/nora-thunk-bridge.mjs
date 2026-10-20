import http from "node:http";
import fs from "node:fs";
import { URL } from "node:url";
import { ThunkStore } from "./thunk-store.mjs";
import { Thunk } from "./thunk.mjs";

const NORA_URL = process.env.NORA_URL || "http://localhost:4000";
const THUNK_SERVER_PORT = process.env.THUNK_SERVER_PORT ? Number(process.env.THUNK_SERVER_PORT) : 9787;
const RELAY_URL = process.env.RELAY_URL || "http://localhost:8787";
const DISCOVERY_ROOM = process.env.DISCOVERY_ROOM || "thunk-servers";
const NORA_STORAGE = "/mnt/data1/nora/storage/cargo";

async function noraFetch(path) {
  return new Promise((resolve, reject) => {
    http
      .get(`${NORA_URL}${path}`, (res) => {
        let data = "";
        res.on("data", (chunk) => (data += chunk));
        res.on("end", () => resolve({ status: res.statusCode, data }));
        res.on("error", reject);
      })
      .on("error", reject);
  });
}

async function noraCrateList() {
  // Read available crate names from Nora's cargo storage directory.
  if (!fs.existsSync(NORA_STORAGE)) {
    throw new Error(`Nora storage not found: ${NORA_STORAGE}`);
  }
  const entries = fs.readdirSync(NORA_STORAGE);
  const crates = [];
  for (const entry of entries) {
    const path = `${NORA_STORAGE}/${entry}/metadata.json`;
    if (fs.existsSync(path)) {
      try {
        const meta = JSON.parse(fs.readFileSync(path, "utf8"));
        const crate = meta.crate;
        if (!crate) continue;
        // Version is stored in the versions array, not at the top level.
        const version = crate.versions && crate.versions.length > 0
          ? crate.versions[0].num
          : crate.max_version || "0.0.1";
        crates.push({
          name: crate.name,
          version,
          path,
        });
      } catch {
        // Not a valid crate; skip it.
      }
    }
  }
  return crates.filter(c => c.name && c.version);
}

function makeThunkFromCrate(crate) {
  const name = crate.name || "unknown";
  const version = crate.version || "0.0.1";
  const source = `// Nora-published crate: ${name} v${version}
const MAX_LINES = 4096;

function reduce(state, input) {
  // Thunk represents the ${name} crate at ${version}
  // State is the crate's metadata snapshot
  if (input.type === "fetch") {
    return {
      ...state,
      fetched: true,
      crate: "${name}",
      version: "${version}",
    };
  }
  if (input.type === "manifest") {
    return {
      ...state,
      manifest: input.manifest,
    };
  }
  return state;
}

module.exports = { reduce, initialState: { fetched: false, crate: "", version: "", manifest: null } };
`;

  return {
    name,
    version,
    source,
  };
}

async function storeThunk(thunk) {
  const store = new ThunkStore("/tmp/thunks-bridge");
  const thunkObj = await Thunk.load(thunk.source, thunk.name, thunk.version);
  const id = store.store(thunkObj);
  return id;
}

async function advertiseOnRelay(thunkId, name, version) {
  try {
    const WebSocket = (await import("ws")).default;
    const wsUrl = new URL(`/ws/${DISCOVERY_ROOM}`, RELAY_URL).toString();
    const socket = new WebSocket(wsUrl);

    return new Promise((resolve) => {
      socket.on("open", () => {
        socket.send(
          JSON.stringify({
            type: "thunk-announce",
            thunkId,
            name,
            version,
          })
        );
        setTimeout(() => {
          socket.close();
          resolve(true);
        }, 500);
      });
      socket.on("error", (e) => {
        console.error(`[bridge] relay announce error: ${e.message}`);
        resolve(false);
      });
      socket.on("close", () => resolve(true));
    });
  } catch (e) {
    console.error(`[bridge] relay connection failed: ${e.message}`);
    return false;
  }
}

async function main() {
  console.log(`[nora-thunk-bridge] starting: NORA=${NORA_URL} THUNK=${THUNK_SERVER_PORT} RELAY=${RELAY_URL}`);

  // Fetch available crates from Nora storage.
  const crates = await noraCrateList();
  console.log(`[nora-thunk-bridge] fetched ${crates.length} crates from Nora storage (${NORA_STORAGE})`);

  // For each crate, create a thunk and publish via p2p.
  const published = [];
  for (const crate of crates) {
    try {
      const thunk = makeThunkFromCrate(crate);
      const id = await storeThunk(thunk);
      const announced = await advertiseOnRelay(id, thunk.name, thunk.version);
      published.push({
        crate: crate.name,
        version: crate.version,
        thunkId: id,
        ok: true,
        announced,
      });
      console.log(`[nora-thunk-bridge] ${crate.name}@${crate.version} -> ${id} (announced: ${announced})`);
    } catch (e) {
      console.error(`[nora-thunk-bridge] error for ${crate.name}: ${e.message}`);
      published.push({ crate: crate.name, ok: false, error: e.message });
    }
  }

  // Advertise what's available on the relay.
  console.log(`[nora-thunk-bridge] published ${published.length} thunks`);
  const okCount = published.filter((p) => p.ok).length;
  console.log(`[nora-thunk-bridge] ${okCount}/${published.length} successful`);

  process.exit(0);
}

main().catch((e) => {
  console.error(`[nora-thunk-bridge] fatal`, e);
  process.exit(1);
});