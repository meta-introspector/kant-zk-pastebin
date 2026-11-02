# Task: encrypted-static-p2p-publish

- **Name:** encrypted-static-p2p-publish
- **Priority:** P0
- **Area:** cloudflare, crypto, p2p, static, capability
- **Status:** **All three modules complete (`515d0343`). Not yet wired to a route or deployed.**
- **Created:** 2026-10-04
- **Follows:** PB-40 (thunk-relay hardening landed the same day)
- **Tags:** cloudflare, crypto, p2p, static, capability

## What was asked

Operator, 2026-10-04: publish to a Cloudflare site —

- **encrypted source**
- **public wrapper**
- **gated execution engine with ACLs**
- **stateless P2P web app, static**

Operator constraints added 2026-10-04:

- **Use our own P2P relay and our own Web Worker** — do not depend on a third-party
  rendezvous. Both exist and are deployable (see Assets).
- **The website must be immutable** — resolved as: **content-hash versioned
  deploys.** Every build is a new immutable root under its hash; earlier versions
  stay fetchable forever; a pointer names the current one. Content never mutates
  in place — new content is a new URL.

## Why the order matters

This follows immediately after PB-40, and inherits two of its results:

- `thunk-relay-control` demonstrated that **a view needs no authority** — it
  holds the relay token server-side and the browser never sees it. That is the
  pattern for "gated execution": the gate decides, the client displays.
- The non-vacuity work established that **a check nothing can fail is
  decoration.** The gate must be shown to refuse, not merely to exist.

## The tension, stated plainly

Three of the four requirements pull against each other.

**"Stateless" vs "ACLs".** An access control list is state. Something must
remember who is allowed what. Either:

- **a)** state lives in a Durable Object — which contradicts "stateless", and
  re-opens the DO cost question PB-30 settled (`11,059 GB-s/day per
  always-on room` = 85% of the free tier); or
- **b)** identity is a **signed capability token**, and the app is stateless
  because authorisation is carried in the credential rather than looked up.
  This satisfies both readings, and is the option worth taking.

**"Encrypted source" vs "public".** A public CDN distributes to everyone. If the
key is in the wrapper, the source is encrypted in transit and clear on arrival —
protection against a scraping bot, not against a reader. So:

- Who holds the key? If it ships to the client, the source is not really secret
  from anyone who opens devtools.
- If the intent is *source-available but not trivially copyable*, say so — that
  is a different and honest goal than *secret source*.
- If the intent is protecting **the operator's IP in the published artefact**,
  then the ciphertext must be meaningful to a client that legitimately holds a
  key — which means key distribution is the whole problem, and it is unsolved by
  encryption alone.

**This needs an explicit threat model before code.** Encrypting source on a public
CDN invites the question "against whom, specifically?" and the honest answers
lead to very different designs.

**"Stateless P2P" vs discovery.** WebRTC peers need a rendezvous to find each
other. A static site has nowhere to put one. Options: a DO (same cost problem),
the existing `thunk-relay` on :8971 (already authenticated, already reachable via
cloudflared), or a public rendezvous that is not ours. **The relay already solves
this** — that is worth reusing rather than rebuilding.

## What immutability settles — and the one problem it creates

Immutability plus content-hashing resolves three of the open questions cleanly:

- **"stateless" vs "ACLs"** — a hash has no mutable lookup table. Authorisation
  must therefore travel in the credential, so **signed capability tokens** are
  forced by the architecture, not chosen by preference. No Durable Object needed,
  so PB-30's DO cost problem does not arise.
- **"encrypted source"** — `source.enc` is itself content-addressed, so its
  ciphertext hash is part of its identity and tampering is detectable by hash
  alone.
- **P2P discovery** — the relay does rendezvous. Already authenticated,
  already publicly reachable, already content-addressed.

### The consequence to decide: immutability forbids a baked-in key

**A public wrapper that never changes cannot carry a rotating key.** Every
deployment is permanent and fetchable forever, so a key placed in the wrapper is
published in cleartext for the lifetime of the site, and rotating it means a new
deploy rather than a secret rotation.

So the key must arrive from outside the artefact. Candidates:

1. **The relay issues it** — a client authenticates, the relay returns or
   unwraps the key. Keeps the "view holds no authority" pattern from PB-40; the
   browser still never holds a long-lived secret. **Recommended.**
2. **User-supplied** — the key comes from the operator's own credential store.
   Strongest, but every user needs one provisioned.
3. **Key in the wrapper** — rejected: contradicts immutability.

Whichever is chosen, state the threat model honestly. Encryption protecting an
artefact from casual scraping is a real and modest goal; protection from a
determined reader is not achievable with a public CDN.

### One single point of trust

With the site immutable, the **only mutable thing is the pointer** naming the
current hash. That is a genuine single point of failure: whoever can write the
pointer decides what users get. Worth pinning the pointer's hash somewhere the
Worker's operator controls, so a compromised pointer is detectable.

## Assets that already exist — build on these, do not rebuild

| asset | what it gives us |
|---|---|
| `thunk-relay` (:8971) | authenticated, nix-managed, publicly reachable, content-addressed; store-and-move, never executes |
| `thunk-relay-control` | the "view holds no authority" pattern — token server-side, never in the browser |
| `peer/storm-peer.mjs` + `peer/wrangler.toml` | **our own Worker**: /health /state /probe /publish /round, host-pinned roster |
| `lib/peer-protocol.mjs` | signed peer events, canonical DAG-CBOR preimages, credential denylist |
| `lib/peer-roster.mjs` | host-pinned signed roster, monotonic seq, revocation |
| `lib/cbor-canonical.mjs` | ESM port of the canonical encoder, byte-parity tested |
| PB-37 wasm thunks | `assertFragment` refuses a module that outgrew the proved fragment |

`peer/storm-peer.mjs` already refuses to boot if any credential-shaped binding
exists (`startupProblem`), which is the right default for the gate.

Note: `kant-libp2p.mjs` / `kant-helia.mjs` / `kant-ipfs.mjs` are **not on main**
(PB-35 — they exist only on `wip/deploy-checkout-20261003`). Do not assume IPFS is
available without triaging that branch first.

## Candidate shape

Assuming capability-token identity and relay-based discovery:

```
Cloudflare (static)
  index.html          public wrapper — UI only, no source, no secret
  engine.wasm         gated execution engine — runs only with a valid capability
  source.enc          encrypted source; useless without the key

thunk-relay (:8971, already deployed + authenticated)
  holds capability keys server-side; signs/verifies; never ships them
  rendezvous for peer discovery
```

The relay is doing the job it was built for — **store and move, never execute**.
A capability it signs is a thing it moves. That constraint survives.

## Decision 2026-10-04 — the Worker is trusted, the network is not

Operator ruling, resolving the key-storage question:

> the worker can have a private keyring, it can serve functions by decoding the
> programs and loading them **or** the programs are unlocked and read directly so
> it does not need to decrypt every time. it has private access. otherwise the
> public data is encrypted or access controlled.

As implemented, this means:

| concern | ruling | where the cost lands |
|---|---|---|
| **programs** | stored **unencrypted** server-side (private bucket); Worker reads them directly | publish time only — **never in the request path** |
| **keyring** | still held, privately, but **only for the publish path** (encrypt-on-write) and for private/public data scoping | not in the hot path |
| **public data** | **capability-gated** (signed tokens), not encrypted | the gate is the access control |
| **key material** | Worker secret (`wrangler secret put`) — never baked in, never in git, never printed | — |

**Why this is coherent with immutability.** Ciphertext-vs-plaintext is orthogonal
to content-addressing. Storing plaintext in a private bucket does not weaken
immutability; it just moves decryption off the per-request path entirely. The
key still arrives from outside the artefact, so the "wrapper cannot carry a
rotating key" problem is unchanged and still governs.

**Why the gate carries the weight, not the crypto.** Encryption on *public* data
buys nothing against a determined reader of a public bucket — they have the
ciphertext and they are the adversary. So access control for public data is
**capability tokens**, and encryption is reserved for the genuinely private
payloads. Stating it this way is the honest version of "encrypted source".

### Two consequences that constrain the build

1. **The Worker's private access is now the entire trust boundary.** Deployment
   must therefore be genuinely private — a named Cloudflare tunnel or Access in
   front, bucket non-public. The current quick-tunnel URL (ephemeral
   `trycloudflare.com`) is fine for the relay test and is **wrong footing here**.
2. **The capability gate is the only thing stopping anonymous execution, and it
   must fail closed** — **503 when the signing key is unset**, **401 when the
   token is wrong**, distinct so "no key set" stays diagnosable. This is exactly
   the bug class PB-40 just fixed in `requireRelayAuth` (`thunk-relay.mjs` had
   *no* auth at all), so it is a pattern to reuse, not a novel risk.

## Built 2026-10-04 — commit `c84b4a9f` (branch `pb41/publish-engine`)

Worktree: `~/projects/twitterstorm/worktrees/pb41-publish` (fresh, off
`origin/main` = `3fbc9eb6`; `node_modules` symlinked from the main checkout
because the pre-commit gate's tsc stage needs it).

| file | what it is |
|---|---|
| `lib/publish/immutable.mjs` | content-hash roots, canonical manifest, pointer + pin |
| `lib/publish/capability.mjs` | the fail-closed gate (503/401/403 kept distinct) |
| `lib/test/publish-gate.test.mjs` | **34 tests**, offline, no network |
| `lib/test/publish-non-vacuity.mjs` | **19/19 mutations caught** |

Both modules are **runtime-neutral — WebCrypto only, zero `node:` imports** — so
the Worker and the test suite run the *same* code. A gate that exists on only
one side of the deploy is half a gate.

Nothing is wired to a route yet, by design: the gate and the store are provable
before anything is reachable.

### Three decisions worth keeping

1. **The manifest is length-prefixed, not delimiter-joined.** A `path:hash\n`
   encoding makes `{p, "q:"+H}` and `{"p:q", H}` serialise to *identical bytes*
   — two deployments claiming one root, chosen on purpose by an attacker. The
   first framing test I wrote did not actually collide and the mutation
   **survived**; the surviving mutation is what forced the real forgery, and it
   is now caught. Worth remembering: a non-vacuity survivor is information, not
   an obstacle.
2. **`503 ≠ 401` is load-bearing.** Collapsing them sends an operator hunting
   for an attacker instead of reading their own deploy. Same reasoning as
   `requireRelayAuth`; repeated deliberately.
3. **Scope is checked *after* the signature.** Checking it first would let an
   unauthenticated caller enumerate which scopes exist by watching 403 vs 401.
   Pinned by a mutation.

### Suite state

- Publish suite: **34/34 pass**, non-vacuity **19/19 caught**.
- 6-stage pre-commit gate: **PASSED**.
- Full `lib/test/*.test.mjs`: 226 tests, 222 pass, **4 fail** — all four in
  `peer-worker.test.mjs`, all `TypeError: fetch failed / ECONNRESET`. That file
  and `peer/` are byte-identical to `origin/main` and nothing imports the new
  modules, so these are **pre-existing and unrelated** — they need a live
  endpoint this worktree does not have. Not triaged; recorded here rather than
  glossed.


## Corrected 2026-10-04 — `7be8d226`: roots are DAG-CBOR CIDs

Operator: *"this is the entire problem that dag-cbor ipld was trying to solve with
deterministic cids"*. Correct, and the cost was **identity, not framing**.

A root computed as **bare sha256 hex is not a CID**. It cannot be passed to
`link()`; nothing that speaks IPLD can address it; it cannot be compared against
content the relay already stores. My length-prefixed manifest format was also
re-implementing, worse, a property DAG-CBOR already has — the encoding is
self-delimiting, so no path can contain anything that changes how it parses.

Now: deploy root = **CIDv1 over a DAG-CBOR manifest**; each file named by the
**CID of its bytes**. A deploy root is a node in the same content graph as the
thunks and tiles, not a private namespace beside it.

This required **completing the ESM port**: `lib/cbor-canonical.mjs` had
`cborEncode` and `cidBytes` but no way to *build* a CID and no decoder.
`cidOf`, `verifyCid`, `sha256`, `base32Encode`, `cborDecode` are re-typed from
`lean/web/core.js` and pinned by the parity test that already exists for exactly
this hazard. The digest is **WebCrypto, not a third hand-written sha256** — a
hand-written digest should exist once — and the test asserts what matters: the
two implementations produce **byte-identical addresses**.

Two smaller corrections that fell out of it:

- **`verifyManifest` takes BYTES, not a parsed object.** Re-encoding an object
  would verify *our idea of* the manifest rather than what was actually stored.
- **Per-file verification is separate from manifest verification.** A
  correctly-addressed tree says nothing about the bytes a fetch returned.

### What the harness found this time

Two `verifyCid` mutations survived, and the cause was **a real gap in my tests,
not a bad mutation**: base32 decode is **not injective**. For one digest, the
final characters `f`, `g` and `h` all decode to the *same 36 bytes* — so a
non-canonical address has the right length, the right version byte, the right
multihash prefix and the right digest, and passes every structural check there
is. Only re-encoding catches it. `core.js` already guards this; my tests did not
exercise that shape at all. The test now derives its variants rather than
hardcoding them, since which characters collide depends on the digest's low bits.

The third survivor was **declared equivalent with a written reason** rather than
papered over: the strict length check in `verifyCid` is redundant with the
canonicality check that follows it, so no test can distinguish its presence from
its absence. The harness now records that outcome **separately from a survivor**,
because *"this is not tested"* and *"this is not testable"* are different
claims and only the first is actionable.

### Suite state

- `lib/test/publish-gate.test.mjs` — **44 pass**
- `lib/test/cbor-canonical-parity.test.mjs` — **11 pass** (7 new, all CID/decoder)
- non-vacuity — **29/30 caught, 1 declared equivalent**, across three modules now
- 6-stage pre-commit gate — **PASSED**
- full `lib/test/*.test.mjs` — 243 tests / 240 pass / **3 fail**, all
  `peer-worker.test.mjs`, all `workerd` + real DNS (`probe.invalid`). Pre-existing.


## Closed 2026-10-04 — the two remaining open items

Both questions PB-41 left open are now answered in code, not just prose.

### 1. Where the pin lives — `0319f2f4`

`checkPointer` took a `pinnedRoot` and **nothing supplied one**, so tamper
detection was inert. Worse, the shape invited the wrong implementation:
`PIN_KEY` sat in the **same store as the pointer**, which makes it no pin at
all. Anyone who can write the pointer can write the pin, so the comparison
would be the attacker's value against itself — passing.

**A pin has to live somewhere the pointer-writer cannot reach.** It now comes
from the Worker's own configuration (`pinFromEnv`), and the store is never
asked where the truth is. `PIN_KEY` remains, documented as the operator's
*record* of the last blessed root — useful for a dashboard, worthless for
detection, labelled so nobody mistakes it for a control.

The status that matters is **`unpinned`**: a deploy with no pin has no tamper
detection, and if that reported `pinned-ok` an operator would read
*protected* on a dashboard detecting nothing. `unpinned` serves but alerts;
`moved` and `corrupt` block; `unknown` is a cold store and does neither. An
unrecognised status does **not** fall through to serve.

The test **simulates the attack end to end** rather than describing it: store
fully attacker-controlled, pointer *and* in-store pin both rewritten. Without
an external pin → `unpinned`. With it → `moved`. Both halves asserted, so the
store-only-pin design cannot come back.

### 2. Per-scope TTL — `515d0343`

There is **no revocation list** (a hash has no lookup table to put one in), so
a capability's lifetime *is* the revocation story. TTL is a security parameter,
not a convenience:

| scope | TTL | why |
|---|---|---|
| `read` | 1 hour | fetches public data; little to protect |
| `execute` | **5 minutes** | runs the engine; the expensive failure |
| unknown | **5 minutes** | fails toward caution |

**Execute is shorter, deliberately.** The intuition runs the other way —
execute is the capability people expect to *keep*. It is exactly why it should
not: the gate is stateless, the token cannot be taken back, and lifetime is the
only lever left. Needing a long-lived execute token means asking for a property
this architecture does not have; the answer is a shorter deploy cycle or a
stateful store, **not a bigger TTL**.

Unknown scopes default to the **strictest** value: defaulting them to `read`
would mean every scope added later is quietly born over-permissioned.

### Suite state

- `lib/test/publish-gate.test.mjs` — **55 pass**
- `lib/test/cbor-canonical-parity.test.mjs` — **11 pass**
- non-vacuity — **40/41 caught, 1 declared equivalent**, three modules
- 6-stage pre-commit gate — **PASSED** on all three commits
- full `lib/test/*.test.mjs` — 254 tests / 253 pass / **1 fail**,
  `peer-worker.test.mjs`, `workerd` + real DNS. **Pre-existing**; the count
  drifts 3–4 between runs because these are network-timing dependent.

### What is deliberately still not done

- **Nothing is wired to a route.** The gate, the store and the pointer policy
  are provable before anything is reachable; a route makes them deployable and
  therefore reachable.
- **No Cloudflare deploy.** Needs account credentials surfaced by name only.
- **`thunk-relay.mjs`'s `cidOf` is still bare sha256 hex.** Two identity schemes
  now coexist in one repo — the milder form of the *two encoders, one
  signature* problem. It belongs in its own task because it changes how
  already-stored blobs are named.

### Deliberately NOT folded in

`thunk-relay/thunk-relay.mjs`'s `cidOf` is **also** bare sha256 hex with no
multihash. Fixing only the publish module leaves **two identity schemes in one
repo**, which is the milder form of the *"two encoders, one signature"* failure.
That should be its own task: it touches how the relay names already-stored
blobs.

## Open questions — answered 2026-10-04

1. **Threat model.** Resolved above: the Worker is inside the boundary and
   trusted; the network is not. Public data is capability-gated; genuinely
   private payloads are encrypted. Encryption protecting a *public* artefact
   from a determined reader is not achievable and is not claimed.
2. **Who holds the key.** The Worker holds it privately, as a secret. It never
   ships in the immutable wrapper.
3. **Stateless.** A hash has no mutable lookup table, so **no Durable Object** —
   PB-30's cost question does not arise. Identity travels in the credential.
4. **Capability tokens, not a lookup.** (For the signing key's identity vs. the
   relay's existing token: default to a **separate** capability signing key so
   revoking gate access does not disturb relay operations.)
5. **Rendezvous.** Reuse the relay on :8971 — already authenticated, already
   reachable.
6. **"Gated execution"** executes wasm thunks, connecting to PB-37 and
   `assertFragment`, which refuses a module that outgrew the proved fragment.

Both answered in code — see *Closed 2026-10-04* below. The pin comes from
Worker configuration rather than the store, and TTL is per scope with `execute`
the short one.

**Answered at build time:** token format is `base64url(canonicalJSON).base64url(HMAC-SHA256)`,
signed over the *encoded* segment; `exp` is mandatory, default TTL 3600 s,
`leewaySeconds` default 30.

## Superseded open questions

<details><summary>Original framing, before the ruling (kept for the reasoning)</summary>

1. **Threat model.** Who is the adversary: a scraper, a reader, Cloudflare, or a
   future maintainer? Determines whether encryption is worth anything.
2. **Who holds the key**, and how does a legitimate client get it without the
   wrapper carrying it?
3. **Does "stateless" forbid Durable Objects**, or mean the *app* is stateless
   while identity is not? PB-30 already priced the DO alternative.
4. **Capability tokens or a lookup?** If tokens, what signs them — and is the
   signing key the relay's existing token, or a separate one?
5. **Reuse the relay for rendezvous**, or a separate signalling path?
6. **What does "gated execution" actually execute** — wasm thunks? If so, this
   connects to PB-37 and the fragment gate (`assertFragment` refuses a module
   that outgrew the proved fragment).

</details>

## Existing assets to reuse, not rebuild

- `thunk-relay` — authenticated, nix-managed, publicly reachable, content-addressed
- `thunk-relay/control-plane.mjs` — the "view holds no authority" pattern
- PB-37 wasm thunks with inline Lean provenance + `assertFragment`
- PB-30 DO duration arithmetic, if DOs turn out to be unavoidable
- `secrets/credentials.enc.json` — sops registry; CF API tokens present, but those
  are for the CF API and are **not** tunnel or capability credentials

## Note

Cloudflare Pages/Workers account credentials are in sops but not in the
environment. Any deploy step needs the account id and a token surfaced by name
only — never printed, never in a committed config.
