import { readFileSync, readSync } from 'node:fs';

function verify() {
    const module = new WebAssembly.Module(readFileSync(process.argv[2]));
    if (WebAssembly.Module.imports(module).length !== 0) {
        throw new Error('Unexpected WASM import');
    }
    const { memory, frame_ptr, frame_capacity, verify } = new WebAssembly.Instance(module).exports;
    const capacity = 20 + 4096 + 64 + 32 + 1048576 + 64;
    if (frame_capacity() !== capacity) {
        throw new Error('Unexpected frame capacity');
    }
    if (process.argv[3] === '--audit-abi') {
        if (verify(capacity + 1) !== 3) {
            throw new Error('WASM bounds check failed');
        }
        const pages = memory.buffer.byteLength / 65536;
        memory.grow(64 - pages);
        try {
            memory.grow(1);
            throw new Error('WASM memory exceeded cap');
        } catch (error) {
            if (!(error instanceof RangeError)) throw error;
        }
        return 3;
    }
    const frame = Buffer.alloc(capacity + 1);
    let length = 0;
    while (length < frame.length) {
        const count = readSync(0, frame, length, frame.length - length);
        if (count === 0) break;
        length += count;
    }
    if (length <= capacity) {
        new Uint8Array(memory.buffer, frame_ptr(), length).set(frame.subarray(0, length));
    }
    return verify(length);
}

try {
    console.log(verify());
} catch {
    console.log(8);
}
