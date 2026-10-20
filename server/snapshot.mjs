// server/snapshot.mjs — snapshot and restore a server as a static worker.
//
// Usage:
//   import { snapshotServer, restoreServer } from "./snapshot.mjs";
//   const snap = await snapshotServer(server);
//   writeFile("worker-snapshot.json", JSON.stringify(snap));
//   const server2 = await restoreServer(JSON.parse(await readFile("worker-snapshot.json")));

import { readFile, writeFile } from "node:fs/promises";
import { Thunk } from "./thunk.mjs";

/**
 * Snapshot a running server.
 * @param {Server} server
 * @returns {{ manifest: object, state: object, timestamp: number }}
 */
export async function snapshotServer(server) {
  const manifest = {
    thunks: [],
    schedule: server.schedule ? server.schedule.manifest() : [],
  };

  // Snapshot each stored thunk
  for (const { id } of server.thunkStore.list()) {
    try {
      const share = await server.thunkStore.snapshot(id);
      manifest.thunks.push({ id, share });
    } catch (e) {
      console.warn(`[snapshot] failed to snapshot thunk ${id}:`, e);
    }
  }

  return {
    manifest,
    state: server.report(),
    timestamp: Date.now(),
  };
}

/**
 * Restore a server from a snapshot.
 * @param {{ manifest: object, state: object, timestamp: number }} snap
 * @param {object} env  // port, store dir, etc.
 * @returns {Promise<Server>}
 */
export async function restoreServer(snap, env = {}) {
  const server = new Server(env);

  // Restore thunks from their shares
  for (const { id, share } of snap.manifest.thunks) {
    try {
      const thunk = await Thunk.restore(share);
      server.thunkStore.store(thunk);
    } catch (e) {
      console.warn(`[restore] failed to restore thunk ${id}:`, e);
    }
  }

  // Restore schedule if provided
  if (snap.manifest.schedule && server.schedule) {
    server.schedule.installManifest(snap.manifest.schedule);
  }

  // Note: the server's runtime state (results, errors, etc.) is not restored;
  // a fresh server starts clean. The thunks themselves hold the state.
  return server;
}
