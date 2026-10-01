/* tslint:disable */
/* eslint-disable */

export function deploy_project(project_id: string, project_name: string, domain: string): Promise<any>;

export function fetch_project(project_id: string): Promise<any>;

export function fetch_project_list(): Promise<any>;

export function generate_deploy_config(project_id: string, project_name: string, domain: string): string;

export function get_api_base_url(): string;

export function get_api_key(): string | undefined;

export function get_cloudflare_account_id(): string;

export function get_cloudflare_default_domain(): string;

export function get_deploy_instructions(project_id: string, project_name: string, domain: string): string;

export function init_panic_hook(): void;

export function set_api_key(key: string): void;

export function validate_project_id(project_id: string): boolean;

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export interface InitOutput {
    readonly memory: WebAssembly.Memory;
    readonly deploy_project: (a: number, b: number, c: number, d: number, e: number, f: number) => any;
    readonly fetch_project: (a: number, b: number) => any;
    readonly fetch_project_list: () => any;
    readonly generate_deploy_config: (a: number, b: number, c: number, d: number, e: number, f: number) => [number, number];
    readonly get_api_base_url: () => [number, number];
    readonly get_api_key: () => [number, number];
    readonly get_cloudflare_account_id: () => [number, number];
    readonly get_cloudflare_default_domain: () => [number, number];
    readonly get_deploy_instructions: (a: number, b: number, c: number, d: number, e: number, f: number) => [number, number];
    readonly init_panic_hook: () => void;
    readonly set_api_key: (a: number, b: number) => void;
    readonly validate_project_id: (a: number, b: number) => number;
    readonly wasm_bindgen__convert__closures_____invoke__h18d997961a3959e1: (a: number, b: number, c: any, d: any) => void;
    readonly wasm_bindgen__convert__closures_____invoke__h691694ef7169a20c: (a: number, b: number, c: any) => [number, number];
    readonly __wbindgen_exn_store: (a: number) => void;
    readonly __externref_table_alloc: () => number;
    readonly __wbindgen_externrefs: WebAssembly.Table;
    readonly __wbindgen_free: (a: number, b: number, c: number) => void;
    readonly __wbindgen_malloc: (a: number, b: number) => number;
    readonly __wbindgen_realloc: (a: number, b: number, c: number, d: number) => number;
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
