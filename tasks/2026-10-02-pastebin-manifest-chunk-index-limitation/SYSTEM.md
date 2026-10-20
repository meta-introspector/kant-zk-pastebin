# Task: pastebin-manifest-chunk-index-limitation

**Status:** open — a format decision, not a bug
**Project:** kant/pastebin
**Found:** 2026-10-02

## Problem

`decryptFile(secret, manifest, fetchChunk)` derives the chunk index from the
**position in `cids`**. The manifest has no index field. Consequences:

* a one-chunk manifest can only ever mean chunk 0;
* reordering or duplicating an entry in `cids` silently changes which chunk each
  position means;
* a peer cannot resume a partial fetch, because "which chunk am I on" is not
  recorded anywhere.

None of this breaks the current round trip, and the witness commits to the
`cids` list in order, so a reordered list is refused rather than mis-decrypted.
But the limitation is in the format, and every future change to file sharing
inherits it.

A second, related constraint: `Kant.Bytes.digest` is four salted FNV-1a rounds,
**not a multihash**, so no CID is derivable from a witness. That is why a
manifest carries the witness list *and* the IPFS CID list separately, and why
`decryptFile` takes a witness-keyed fetcher and the caller resolves
witness → CID.

## Fix

Decide, and write it down in the format spec:

1. **Leave it.** Document the constraint next to `decryptFile` so the next
   implementer does not rediscover it (this is the cheap option and is what the
   current tree does).
2. **Add an explicit index** to the manifest, as a new tag so old peers ignore
   it rather than reject it — the same approach `kzat` took over `kzchat`.
   This changes the witness computation, so it is a format version bump and
   wants a Lean statement of the new invariant.

Option 2 is a real change to a self-certifying format; do not do it casually.

## Verify

Whichever is chosen, `scripts/fileshare-capture.mjs` should gain a check that
pins the behaviour down — currently it checks that a substituted chunk is
refused, but nothing pins the index rule.
