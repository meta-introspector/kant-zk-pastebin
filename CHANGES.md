# Unstaged Changes — 2026-04-16T17:26:10Z

## flake.nix / flake.lock

- zkperf input URL changed from local working tree to bare mirror:
  `file:///mnt/data1/kant/pastebin/zkperf` → `file:///mnt/data1/git/github.com/meta-introspector/zkperf.git`
- zkperf ref changed from pinned commit hash to named branch `feat/rebase-all`
- flake.lock updated accordingly (narHash, revCount, lastModified)

## New source files (src/bin/)

### js_interpreter.rs
- OXC-based JS interpreter with execution tracing
- Evaluates variable declarations, literals, call expressions
- Records execution steps with orbifold coordinates (erdfa_dasl)

### js_parser.rs
- CLI tool: parses a JS file via OXC and reports statement count
- Exits non-zero on parse errors

### test_generator.rs
- Generates 194 test cases from Monster group irrep symmetries
- Uses Monster primes to derive orbifold coords per irrep
- Outputs AFL++ seed corpus to `fuzz/corpus/`

## Submodule updates

- `erdfa-canonical`: bindings/rust vendor bump (rust-ipfs v0.11.18-432)
