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
    // Unqualified on purpose. `transducers.reduce(...)` is a method call, so it
    // binds `this` to the host-side transducers object, and that object is a
    // realm bridge straight back to the host Function constructor. Destructured
    // first, `this` is undefined inside the (strict) transducer.
    const { reduce } = this.#compiled.transducers;
    const out = reduce(prev, input);
    // Two dialects in the tree: DESIGN.md and server/example-compactor.mjs
    // return the state itself, server/thunk-test.mjs returns {state, effects}.
    // Unwrap only when there is something to unwrap, so neither shape silently
    // becomes the other's bug.
    const wrapped = out !== null && typeof out === "object" && "state" in out;
    const next = wrapped ? out.state : out;
    const effects = [];
    if (wrapped && Array.isArray(out.effects)) effects.push(...out.effects);
    this.#state = next;
    if (JSON.stringify(prev) !== JSON.stringify(next)) effects.push("state-change");
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
 *
 * The script is compiled INSIDE the context, not in the host and then handed
 * over. That distinction is the whole sandbox: a function built with
 * `new Function` keeps the host realm as its scope, so `runInNewContext` would
 * hand it a context object it can already see straight past — `process`,
 * `fetch` and `Buffer` would all still be there. Compiling in the context means
 * the thunk's global IS the sandbox, and the sandbox contains `module` and
 * nothing else.
 *
 * Policy: no `require`, no `process`, no `Buffer`, no timers, no host globals.
 * A `js` thunk that needs a capability gets it from a declared api set, not
 * from `require` — see tasks/thunk-server/SANDBOX.md for why the one-line
 * alternative was rejected.
 *
 * Dialect: `module.exports = ...`, not ESM. A script body has no `export`, so
 * `export function reduce` is a SyntaxError here by construction.
 */
async function loadSource(source) {
  const vm = await import("node:vm");
  const sandbox = vm.createContext(Object.create(null));
  // `module` is created IN the context, not handed in. A host object placed in
  // a vm context is a bridge: `module.constructor.constructor` walks from it to
  // the host Function constructor and from there to the host global. That was a
  // working escape, found by the probe below and not by the two sandbox tests.
  vm.runInContext("var module = { exports: {} }; var exports = module.exports;", sandbox);

  // Node injects a `console` into every context it creates, which is a live
  // handle on the host's stdout and stderr: a thunk could flood the server log
  // and a log is not a place an untrusted computation gets to write. Found by
  // the probe, not by the tests.
  vm.runInContext("try { delete globalThis.console; } catch (e) {}", sandbox);

  // Default-deny, enforced before compiling rather than during. A thunk that
  // calls `import()` raises ERR_VM_DYNAMIC_IMPORT_CALLBACK_MISSING, which does
  // not respect the thunk's own try/catch and takes the host process down with
  // it -- passing an `importModuleDynamically` callback does not contain it
  // either, which was measured rather than assumed. Refusing to load is the
  // only version of this that cannot stop the server.
  const forbidden = source.match(/\bimport\s*\(|\bimport\s*\.\s*meta\b/);
  if (forbidden) {
    throw new Error(
      `thunk source contains \`${forbidden[0]}\`: a thunk is loaded without module loading`,
    );
  }

  new vm.Script(`"use strict";\n${source}\n`, { filename: "thunk.js" })
    .runInContext(sandbox, { timeout: 2000 });
  return vm.runInContext("module.exports", sandbox);
}
