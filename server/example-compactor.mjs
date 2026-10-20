// server/example-compactor.mjs — an example thunk: the room compactor.
//
// This is the thunk that the systemd scheduler runs periodically. Its state
// is a set of room cursors; each tick it walks the cursor forward and drops
// lines the relay has already acked to all peers. It is the first concrete
// thunk so the host/store/schedule/snapshot pipeline has a real thing to
// round-trip through the disk, across servers (share/restore), and back into
// persistence as a static worker snapshot.
//
// Transducer source is captured as text inside `source` so `Thunk.load` can
// re-create the lambda on another server.

// A thunk is loaded as a vm.Script, which runs as a script (not a module),
// so the dialect is CommonJS: module.exports, not ESM export. The Thunk.load
// compiles the source INSIDE the sandbox context, so `module` exists there.
// This is why we cannot ship ESM thunks — `export function reduce` raises
// Unexpected token 'export' at compile time and there is no loader to fix it.
//
// The example compactor is a single self-contained function that reduces
// state on the `compact` and `tick` input types. It demonstrates the whole
// pipeline: definition -> store -> run -> share -> restore.

const source = `
const MAX_LINES = 4096;

function reduce(state, input) {
  if (input.type === "compact") {
    const room = input.room;
    const cursor = state.cursors[room] ?? 0;
    const maxCursor = (input.logLines ?? 0) + (input.logBase ?? 0);
    state.cursors[room] = Math.max(cursor, maxCursor);
    state.compacted += (input.logLines ?? 0);
    state.lastRun = input.when;
    return state;
  }
  if (input.type === "tick") {
    state.lastTick = input.when;
    return state;
  }
  return state;
}

module.exports = { reduce, initialState: { cursors: {}, compacted: 0, lastTick: 0, lastRun: 0 } };
`;

export { source };
