---
name: thunk-sandbox-policy
priority: HIGH
depends_on: thunk-server
---

# Sandbox policy: default-deny

**Date:** 2026-10-03 · **Status:** decided and implemented · **Companion to**
[WASM.md](WASM.md), [THUNK-CYCLE.md](THUNK-CYCLE.md), [SYSTEM.md](SYSTEM.md)

## The decision

**A `js` thunk gets no host capability of any kind.** The context it runs in
contains `module`, `exports`, and the JavaScript intrinsics. No `require`, no
`process`, no `Buffer`, no `fetch`, no timers, no `console`, no module loading of
any kind. A thunk that needs a capability gets it from a **declared api set**
([THUNK-CYCLE.md](THUNK-CYCLE.md) point 2), which is part of the call id — not
from `require`.

The dialect is `module.exports = ...`, not ESM. A script body has no `export`,
so `export function reduce` is a SyntaxError by construction rather than by
accident.

## Why not `createRequire`

The one-line fix for the loader bug was `createRequire(import.meta.url)`. It is
also what turns the isolation comment into a lie. Measured, in a scratch copy:

```
require("node:child_process").execSync("id -u")   ->   REACHED:1000
```

A thunk spawned a process and read the uid. So the choice was never "fix the
loader or leave it broken" — it was "fix the loader and hand every thunk the
host", or "fix the loader and hand it nothing".

**Rejected: `createRequire`.** The whole module graph becomes reachable, and a
module allowlist on top of it is a denylist in disguise: `node:child_process`
versus an alias versus `process.binding`, each a different spelling of the same
authority.

**Rejected: `require` plus an allowlist.** Better, still two ways out — any
allowed module that can reach the network, and `require("node:module")` itself.
More importantly it puts an *undeclared* capability mechanism in the path, and
an undeclared capability is exactly what the api set exists to prevent. Two
mechanisms for the same power means the weaker one is the one that gets used.

**Kept for later: a worker or subprocess.** That is real isolation, and it is the
right answer if a future `js` payload genuinely needs it. It is not needed to make
loading work, and adopting it now would make phase 0 a rewrite — and it moves the
trust boundary, because then the *scheduler* has to be trusted too.

## Why the stricter option for `js`

[WASM.md](WASM.md) already decided the payload direction: `web/kant_kernel.wasm`
is 799 bytes with **zero imports**, so for that payload there is no policy to get
wrong. `js` is the transitional path. A transitional path should be the
stricter of the two, not the looser one with a comment attached.

## What the tests did not catch, and what did

The first fix made both sandbox tests in `server/thunk-test.mjs` pass on the
spot — a thunk could no longer `require("node:fs")` or `execSync`. The sandbox
was still open in three places, and none of them was visible from those two
tests:

| escape | why the two tests missed it | fix |
|---|---|---|
| `module.constructor.constructor("return typeof process")()` | a *host object* placed in a vm context is a realm bridge to the host `Function` constructor and from there to the host global | create `module`/`exports` **inside** the context |
| `this.constructor.constructor(...)` inside a transducer | `transducers.reduce(...)` is a method call, so `this` binds to the host-side transducers object — the same bridge by another name | destructure `reduce` first so the call is unqualified and `this` is `undefined` |
| `console.log` from a thunk | Node injects `console` into every context it creates, and a log is a live handle on the host's stdout | `delete globalThis.console` before loading |

And one that was not an escape but was a denial of service: a thunk calling
`import()` raises `ERR_VM_DYNAMIC_IMPORT_CALLBACK_MISSING`, which **ignores the
thunk's own `try`/`catch` and takes the host process down**. Supplying an
`importModuleDynamically` callback did not contain it. So the refusal is at load
time, before compilation: a source containing `import(` or `import.meta` does not
load.

So `server/sandbox-test.mjs` exists and enumerates 13 escapes instead of testing
one. It also asserts that a *pure* thunk still works, because a sandbox that
refuses everything is not a sandbox, it is an outage.

## Known limits of this policy

- **`vm` is not a security boundary in the strong sense.** It is a fresh realm
  with no host authority, which is what the design needs, but a determined
  attacker against a future Node release is a different proposition. The
  long-term answer is wasm, where the answer is structural.
- **`Date` is available**, so a `js` thunk is not deterministic. Same input, same
  id, different output — which means a `js` thunk's result is not content-
  addressable in the way a zero-import wasm result is. That is an argument for
  wasm, not a defect in the sandbox.
- **Cross-realm `instanceof` fails.** Objects made in the vm are not instances of
  the host's `Object`. Anything crossing the boundary should be checked with
  `Array.isArray` / `typeof`, which are realm-agnostic.
- **CPU and memory are not bounded.** `timeout: 2000` bounds a single synchronous
  call and nothing else: no memory cap, no cap across calls, and an infinite loop
  inside an async thunk is outside the timeout entirely.
- **The api set does not exist yet.** The policy says capability comes from a
  declared api set; until [THUNK-CYCLE.md](THUNK-CYCLE.md) phase 3 lands, a `js`
  thunk that needs the filesystem simply cannot have it. That is the correct
  interim state — a capability that is refused is recoverable, a capability that
  was ambient is not.

## Dialect debt

`server/example-compactor.mjs` — the one concrete thunk in the tree — is written
in the ESM form (`export function reduce`, returning `state` directly). It does
not parse under this policy and was not converted as part of it, because the
conversion is a decision about the example rather than about the sandbox.
`apply()` already accepts both shapes, so the conversion is mechanical when
someone makes it.

`server/thunk-test.mjs` remains 8/10 green. The two red gates are phase 1 — the
id is still a 16-char prefix where `asWitness` wants 64.