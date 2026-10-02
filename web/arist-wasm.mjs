// arist-wasm.mjs — adapter between the p2p app's experiment protocol and the
// vendored aristotle-wasm module (web/aristotle_wasm.js, wasm-bindgen --target web;
// rebuilt via scripts/build-arist-wasm.sh).
//
// The module is a remote Aristotle client (projects, deploy configs). It needs
// an API key for real network calls; without one, the local introspection
// experiments (validate id, deploy instructions, config generation) still work —
// exactly what a room demo needs. `available()` lets kant-p2p.mjs degrade
// gracefully when the glue files are absent.
//
//   import { available, run } from "./arist-wasm.mjs";
//   run({ op: "validate-project", projectId: "acc-17" })
//   run({ op: "deploy-instructions", projectId, projectName, domain })
//   run({ op: "fetch-project-list", apiKey })   // needs a key, hits the network

let mod = null;

export function available() {
  return mod !== null;
}

async function load() {
  if (mod !== null) return mod;
  try {
    mod = await import("./aristotle_wasm.js");
    mod.default?.().catch(() => {}); // wasm-bindgen `--target web` init, fire and forget
    mod.init_panic_hook?.();
  } catch {
    mod = null;
  }
  return mod;
}

/**
 * Experiment dispatch for kant-p2p.mjs `experiment("arist", args)`.
 * Returns a plain JSON-able object in every path (room lines are strings).
 */
export async function run({ op, apiKey, projectId, projectName, domain } = {}) {
  const m = await load();
  if (!m) return { error: "aristotle-wasm glue not present (run scripts/build-arist-wasm.sh)" };
  if (apiKey) m.set_api_key(apiKey);
  try {
    switch (op) {
      case "validate-project":
        return { op, valid: m.validate_project_id(String(projectId ?? "")) };
      case "deploy-instructions":
        return { op, text: m.get_deploy_instructions(String(projectId), String(projectName ?? projectId), String(domain ?? "example.localhost")) };
      case "deploy-config":
        return { op, config: m.generate_deploy_config(String(projectId), String(projectName ?? projectId), String(domain ?? "example.localhost")) };
      case "api-base":
        return { op, base: m.get_api_base_url() };
      case "fetch-project":
        return { op, project: await m.fetch_project(String(projectId)) };
      case "fetch-project-list":
        return { op, projects: await m.fetch_project_list() };
      default:
        return { error: `unknown arist op: ${op}`, ops: ["validate-project", "deploy-instructions", "deploy-config", "api-base", "fetch-project", "fetch-project-list"] };
    }
  } catch (e) {
    return { error: String(e?.message ?? e) };
  }
}
