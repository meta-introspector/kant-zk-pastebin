/* tslint:disable */
/* eslint-disable */

/**
 * Forget the session: clears wasm memory and expires the cookie. The API key
 * is cleared too, so a sign-out leaves nothing behind.
 */
export function clear_session(): void;

export function deploy_project(project_id: string, project_name: string, domain: string): Promise<any>;

export function fetch_project(project_id: string): Promise<any>;

export function fetch_project_list(): Promise<any>;

/**
 * Build the wrangler Pages deployment config for a project.
 *
 * `domain` falls back to the session's default domain when empty. The account
 * ID is included only if the client supplied one, and `configured` reports
 * whether it did, so a caller can tell a real deployment plan from an
 * incomplete one.
 */
export function generate_deploy_config(project_id: string, project_name: string, domain: string): string;

/**
 * The Aristotle API base URL in effect: the session override when set,
 * otherwise the shared public service endpoint.
 */
export function get_api_base_url(): string;

export function get_api_key(): string | undefined;

/**
 * The Cloudflare account ID supplied by the client, or an empty string when
 * the session has not been configured. There is no built-in fallback.
 */
export function get_cloudflare_account_id(): string;

/**
 * The Pages domain supplied by the client, or an empty string when unset.
 */
export function get_cloudflare_default_domain(): string;

export function get_deploy_instructions(project_id: string, project_name: string, domain: string): string;

/**
 * The current session configuration as JSON. Empty fields mean "not set";
 * they are never filled in from a compiled-in default.
 */
export function get_session_config(): string;

export function init_panic_hook(): void;

/**
 * Hydrate the session from the client-side cookie. Call once on page load;
 * returns `true` if a valid session was restored.
 */
export function load_session_from_cookie(): boolean;

/**
 * Whether the client has supplied an account ID yet.
 */
export function session_is_configured(): boolean;

/**
 * Supply the Aristotle API key. Held in wasm memory only; it is never written
 * to the session cookie and never leaves the browser except in the `x-api-key`
 * request header.
 */
export function set_api_key(key: string): void;

/**
 * Set the session configuration from a JSON object and persist it to the
 * client-side session cookie so it survives a reload. Required keys:
 * `account_id`; optional: `default_domain`, `api_base_url`.
 */
export function set_session_config(json: string): void;

export function validate_project_id(project_id: string): boolean;

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export interface InitOutput {
    readonly memory: WebAssembly.Memory;
    readonly clear_session: () => void;
    readonly deploy_project: (a: number, b: number, c: number, d: number, e: number, f: number) => any;
    readonly fetch_project: (a: number, b: number) => any;
    readonly fetch_project_list: () => any;
    readonly generate_deploy_config: (a: number, b: number, c: number, d: number, e: number, f: number) => [number, number];
    readonly get_api_base_url: () => [number, number];
    readonly get_api_key: () => [number, number];
    readonly get_cloudflare_account_id: () => [number, number];
    readonly get_cloudflare_default_domain: () => [number, number];
    readonly get_deploy_instructions: (a: number, b: number, c: number, d: number, e: number, f: number) => [number, number];
    readonly get_session_config: () => [number, number];
    readonly init_panic_hook: () => void;
    readonly load_session_from_cookie: () => number;
    readonly session_is_configured: () => number;
    readonly set_api_key: (a: number, b: number) => void;
    readonly set_session_config: (a: number, b: number) => [number, number];
    readonly validate_project_id: (a: number, b: number) => number;
    readonly wasm_bindgen__convert__closures_____invoke__h18d997961a3959e1: (a: number, b: number, c: any, d: any) => void;
    readonly wasm_bindgen__convert__closures_____invoke__h691694ef7169a20c: (a: number, b: number, c: any) => [number, number];
    readonly __wbindgen_malloc: (a: number, b: number) => number;
    readonly __wbindgen_realloc: (a: number, b: number, c: number, d: number) => number;
    readonly __wbindgen_exn_store: (a: number) => void;
    readonly __externref_table_alloc: () => number;
    readonly __wbindgen_externrefs: WebAssembly.Table;
    readonly __wbindgen_free: (a: number, b: number, c: number) => void;
    readonly __wbindgen_destroy_closure: (a: number, b: number) => void;
    readonly __externref_table_dealloc: (a: number) => void;
    readonly __wbindgen_start: () => void;
}

export type SyncInitInput = BufferSource | WebAssembly.Module;

/**
 * Instantiates the given `module`, which can either be bytes or
 * a precompiled `WebAssembly.Module`.
 *
 * @param {{ module: SyncInitInput }} module - Passing `SyncInitInput` directly is deprecated.
 *
 * @returns {InitOutput}
 */
export function initSync(module: { module: SyncInitInput } | SyncInitInput): InitOutput;

/**
 * If `module_or_path` is {RequestInfo} or {URL}, makes a request and
 * for everything else, calls `WebAssembly.instantiate` directly.
 *
 * @param {{ module_or_path: InitInput | Promise<InitInput> }} module_or_path - Passing `InitInput` directly is deprecated.
 *
 * @returns {Promise<InitOutput>}
 */
export default function __wbg_init (module_or_path?: { module_or_path: InitInput | Promise<InitInput> } | InitInput | Promise<InitInput>): Promise<InitOutput>;
