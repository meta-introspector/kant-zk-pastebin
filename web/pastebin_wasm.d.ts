/* tslint:disable */
/* eslint-disable */

export function wasm_chunk_plan(size: number): Uint32Array;

export function wasm_cid_identity(cid: string): Uint8Array;

export function wasm_cid_of_bytes(bytes: Uint8Array): string;

export function wasm_kzcid_record(peer: string, name: string, cid: string, size: number, note: string, pinned: boolean, ts: number): string;

export function wasm_parse_kzcid_record(line: string): any;

/**
 * The CID to publish an artifact under — the raw leaf for anything within
 * one chunk, otherwise the UnixFS dag-pb root.
 */
export function wasm_unixfs_cid(bytes: Uint8Array): string;

/**
 * The full transfer plan as JSON: root CID plus every leaf, in order, so the
 * browser can exchange the pieces and reassemble.
 */
export function wasm_unixfs_plan(bytes: Uint8Array): string;

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export interface InitOutput {
    readonly memory: WebAssembly.Memory;
    readonly wasm_chunk_plan: (a: number) => [number, number, number, number];
    readonly wasm_cid_identity: (a: number, b: number) => [number, number, number, number];
    readonly wasm_cid_of_bytes: (a: number, b: number) => [number, number];
    readonly wasm_kzcid_record: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number, j: number, k: number) => [number, number, number, number];
    readonly wasm_parse_kzcid_record: (a: number, b: number) => [number, number, number];
    readonly wasm_unixfs_cid: (a: number, b: number) => [number, number, number, number];
    readonly wasm_unixfs_plan: (a: number, b: number) => [number, number, number, number];
    readonly __wbindgen_externrefs: WebAssembly.Table;
    readonly __externref_table_dealloc: (a: number) => void;
    readonly __wbindgen_free: (a: number, b: number, c: number) => void;
    readonly __wbindgen_malloc: (a: number, b: number) => number;
    readonly __wbindgen_realloc: (a: number, b: number, c: number, d: number) => number;
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
