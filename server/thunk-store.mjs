// server/thunk-store.mjs — store for thunks.
//
// Persists definitions and snapshots on disk so thunks survive
// process restarts. The in-memory cache keeps hot thunks
// fast. Designed so `ThunkStore` can later back onto SQLite
// alongside the relay's existing durable storage.

import { mkdirSync, readFileSync, writeFileSync, readdirSync, statSync, unlinkSync } from "node:fs";
import { join, dirname } from "node:path";
import { Thunk } from "./thunk.mjs";

/**
 * @param {string} dir  directory that holds `thunks/<id>.json`
 */
export class ThunkStore {
  #dir;
  #cache = new Map(); // id -> Thunk

  constructor(dir) {
    this.#dir = dir;
    mkdirSync(dir, { recursive: true });
    this.#loadAll();
  }

  /** Persist a definition + optional initial snapshot; returns id. */
  store(thunk) {
    const id = thunk.id;
    const path = this.#path(id);
    const data = { definition: { name: thunk.name, version: thunk.version, source: thunk.source }, state: thunk.snapshot(), createdAt: Date.now() };
    writeFileSync(path, JSON.stringify(data), "utf8");
    this.#cache.set(id, thunk);
    return id;
  }

  /** Restore a thunk from disk. */
  async get(id) {
    const cached = this.#cache.get(id);
    if (cached === null) {
      const data = this.#read(id);
      if (!data) {
        this.#cache.delete(id);
        return null;
      }
      const t = await Thunk.load(data.definition.source, data.definition.name, data.definition.version);
      t.resume(data.state);
      this.#cache.set(id, t);
      return t;
    }
    if (cached) return cached;
    const data = this.#read(id);
    if (!data) return null;
    const t = await Thunk.load(data.definition.source, data.definition.name, data.definition.version);
    t.resume(data.state);
    this.#cache.set(id, t);
    return t;
  }

  /** All stored thunk summaries. */
  list() {
    const out = [];
    try {
      for (const f of readdirSync(this.#dir)) {
        if (!f.endsWith(".json")) continue;
        const data = JSON.parse(readFileSync(join(this.#dir, f), "utf8"));
        out.push({ id: f.replace(/\.json$/, ""), name: data.definition.name, version: data.definition.version, createdAt: data.createdAt });
      }
    } catch { /* dir missing or corrupt — ignored */ }
    return out.sort((a, b) => b.createdAt - a.createdAt);
  }

  async snapshot(id) {
    const thunk = await this.get(id);
    if (!thunk) throw new Error(`thunk ${id} not found`);
    return thunk.share();
  }

  remove(id) {
    const p = this.#path(id);
    try { statSync(p); } catch { return false; }
    unlinkSync(p);
    this.#cache.delete(id);
    return true;
  }

  #path(id) { return join(this.#dir, `${id}.json`); }
  #read(id) {
    try { return JSON.parse(readFileSync(this.#path(id), "utf8")); } catch { return null; }
  }
  #loadAll() {
    try {
      for (const f of readdirSync(this.#dir)) {
        if (!f.endsWith(".json")) continue;
        const data = JSON.parse(readFileSync(join(this.#dir, f), "utf8"));
        const id = f.replace(/\.json$/, "");
        this.#cache.set(id, null); // placeholder; lazy-load on get
      }
    } catch { /* dir missing */ }
  }
}
