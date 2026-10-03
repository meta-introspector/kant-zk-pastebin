// server/thunk.mjs — a lambda-based state machine: thunk.
//
// A thunk captures its transition lambdas as source text so the
// thunk is serializable and portable. State is a plain snapshot.
//
// Usage:
//   import { Thunk } from "./thunk.mjs";
//   const t = await Thunk.load(source, "room-compactor", "1.0.0");
//   t.apply({ type: "compact", room });
//   const snap = t.snapshot();
//   t.resume(snap);
//   const m  = t.manifest();      // shareable fingerprint, no state

import crypto from "node:crypto";

// ── helpers ─────────────────────────────────────────────────────

const hash = (s) => {
  const d = crypto.createHash("sha256").update(s).digest("hex");
  return d.slice(0, 16);
};

/** Escape a source so it round-trips through JSON safely. */
const esc = (s) => s.replaceAll("\\", "\\\\").replaceAll("`", "\\`").replaceAll("${", "\\${");

/** Strip export/import noise for a compact canonical source. */
const cleanSource = (src) => src
  .replace(/\/\/.*$/gm, "")
  .replace(/\/\*[\s\S]*?\*\//g, "")
  .replace(/\n+/g, "\n")
  .trim();

// ── Thunk class ─────────────────────────────────────────────────

export class Thunk {
  #definition;
  #state;
  #compiled;

  /**
   * @param {{ name: string, version: string, source: string,
   *           initialState: object, schema?: object }} definition
   * @param {object} state
   * @param {{ transducers?: object }} compiled  — vm-compiled lambdas
   */
  constructor(definition, state, compiled) {
    this.#definition = { ...definition };
    this.#state = state;
    this.#compiled = compiled ?? {};
  }

  /** Re-create from the module returned by `loadSource`. */
  static async load(source, name, version, schema = {}) {
    const m = await loadSource(source);
    const initialState = m.initialState ?? {};
    const transducers = {};
    for (const key of Object.keys(m)) {
      if (key === "initialState" || key === "schema" || key === "name" || key === "version") continue;
      if (typeof m[key] === "function") transducers[key] = m[key];
    }
    if (!transducers.reduce) throw new Error("thunk needs a `reduce(state, input)` transducer");
    return new Thunk(
      { name, version, source, initialState, schema },
      { ...initialState },
      { transducers }
    );
  }

  // id built from name + version + hash of canonical source
  get id() {
    return `${this.#definition.name}@${this.#definition.version}:${hash(cleanSource(this.#definition.source))}`;
  }

  get name() { return this.#definition.name; }
  get version() { return this.#definition.version; }
  get state() { return this.#state; }
  get source() { return this.#definition.source; }

  /** Shareable fingerprint — no state, just the definition identity. */
  manifest() {
    return {
      id: this.id,
      name: this.#definition.name,
      version: this.#definition.version,
      sourceHash: hash(this.#definition.source),
      schema: this.#definition.schema ?? null,
    };
  }

  /** Serializable snapshot of the current state. */
  snapshot() {
    return JSON.parse(JSON.stringify(this.#state));
  }

  /** Restore from a snapshot returned by `snapshot()` or `share()`. */
  resume(snapshot) {
    if (snapshot && typeof snapshot === "object") this.#state = snapshot;
  }

  /**
   * Run one transition.
   * @returns {{ state: object, effects: string[] }}
   */
  apply(input) {
    const prev = this.#state;
    this.#state = this.#compiled.transducers.reduce(prev, input);
    const effects = [];
    if (JSON.stringify(prev) !== JSON.stringify(this.#state)) effects.push("state-change");
    return { state: this.#state, effects };
  }

  /** Produce a shareable bundle (definition + current state). */
  share() {
    return {
      manifest: this.manifest(),
      state: this.snapshot(),
      source: this.#definition.source,
    };
  }

  /** Restore a bundle produced by `share()`. */
  static async restore(bundle, schema = {}) {
    const t = await Thunk.load(bundle.source, bundle.manifest.name, bundle.manifest.version, schema);
    t.resume(bundle.state);
    return t;
  }
}

/**
 * Load a thunk source text into an exports object.
 * Uses `vm` so the source runs in a clean scope with no access to
 * the host process.
 */
async function loadSource(source) {
  const { runInNewContext } = await import("node:vm");
  const exports = {};
  const module = { exports };
  const fn = new Function("module", "exports", "require",
    `"use strict";\n${source}\nreturn module.exports;`);
  runInNewContext(fn, { module, exports, require }, { timeout: 2000 });
  return module.exports;
}
