This project was edited by [Aristotle](https://aristotle.harmonic.fun).

To cite Aristotle:
- Tag @Aristotle-Harmonic on GitHub PRs/issues
- Add as co-author to commits:
```
Co-authored-by: Aristotle (Harmonic) <aristotle-harmonic@harmonic.fun>
```

# kant-zk-pastebin, ported to Lean 4

A machine-checked port of the [`meta-introspector/kant-zk-pastebin`](https://github.com/meta-introspector/kant-zk-pastebin)
pastebin (all branches surveyed) into Lean 4, together with a browser client
that implements the same algorithms and is checked against Lean-computed golden
vectors.

The Lean layer is the specification: every data format, address computation,
framing rule, stego embedding, sync rule and credit rule in the system is a Lean
definition, and the properties the original Rust code assumes informally are
stated and proved as theorems. The `web/` layer is an unverified JavaScript
transcription of exactly those definitions, so the running client and the proofs
talk about the same objects.

```
lake build                # builds every Lean module; 0 sorries, 0 warnings
lake exe emitwasm dist    # extracts dist/kant_kernel.wasm from Lean (no C toolchain needed)
node web/test.mjs         # 29 conformance checks of the JS layer against Lean golden vectors
node web/wasm-test.mjs    # validates and runs the extracted .wasm, and cross-checks it
node web/net-test.mjs     # 32 checks of discovery, chat and the relay (incl. a real relay end-to-end)
node web/qr-test.mjs      # 15 checks of the QR encoder used for the chat code
node server/relay.mjs --port 8787 --static web    # the relay + the client, on your own machine
python3 -m http.server -d web 8080   # then open http://localhost:8080/
```

## Rust → Lean module map

| upstream Rust | Lean module | what it covers |
|---|---|---|
| `src/dasl.rs` | `RequestProject/Kant/Dasl.lean` | `0xDA51` content IDs, nested/shard/harmonic-path CIDs, Monster-group primes, orbifold action, XOR merge algebra |
| `src/model.rs`, `src/paste.rs` | `RequestProject/Kant/Paste.lean` | paste records and the content-addressed store |
| `src/paste.rs` (rendering) | `RequestProject/Kant/Erdfa.lean` | eRDFa/HTML escaping |
| `src/storage.rs` | `RequestProject/Kant/Bytes.lean` | blobs, hex, FNV-1a digest, 64-hex-char witnesses |
| `src/sheaf.rs` | `RequestProject/Kant/Sheaf.lean` | DASL type / eigenspace / encoding taxonomy |
| `SNEAKERNET.md` | `RequestProject/Kant/Sneakernet.lean` | channel capacities, 5 MB social limit, chunking, framing, reassembly |
| `SNEAKERNET.md` (covert) | `RequestProject/Kant/Stego.lean` | LSB steganography in PNG/GIF/SVG carriers |
| `IPFS.md` | `RequestProject/Kant/Sync.lean` | IPFS / iroh / libp2p / torrent / archive.org / UUCP / QR-burst sync |
| new (credits) | `RequestProject/Kant/Credits.lean` | serve-to-earn credit ledger |
| new (code movies) | `RequestProject/Kant/CodeMovie.lean` | RLE snippets, Gödel numbering, circuits |
| new (feed) | `RequestProject/Kant/Feed.lean` | the reader's view: rows, search, paging, threads, newest-first ordering |
| new (clipboard) | `RequestProject/Kant/Clipboard.lean` | copy/paste envelope for posts, results and whole pages, plus share links |
| new (memes) | `RequestProject/Kant/Meme.lean` | memes with the post embedded in the picture |
| new (reposts) | `RequestProject/Kant/Repost.lean` | quote reposts that carry the original whole, and share cards |
| new (strips) | `RequestProject/Kant/Strip.lean` | one share spread over several pictures, collected in any order |
| new (discovery) | `RequestProject/Kant/Rendezvous.lean` | how two clients find each other: peer announcements, rosters, and the chat code (QR invite) that names a room |
| new (relay/chat) | `RequestProject/Kant/Relay.lean` | the append-only room log a relay serves, self-certifying chat messages, and the client's view of a room |
| new (text) | `RequestProject/Kant/Text.lean` | ASCII transcoding, field framing, substring search, numeric byte encoding |
| — | `RequestProject/Kant/Pipeline.lean` | end-to-end paste → address → frame → stego → recover theorem |
| — | `RequestProject/Kant/Demo.lean` | `#guard`-checked worked examples of every layer |
| — | `RequestProject/Kant.lean` | aggregator |

## Theorem index

**Bytes / addressing**

- `Kant.Bytes.hexDecode_hexEncode` — hex encoding round-trips.
- `Kant.Bytes.digest_length`, `Kant.Bytes.witness_length` — digests are 32 bytes, witnesses 64 hex chars.
- `Kant.Dasl.decode_mkCid_of_lt`, `Kant.Dasl.mkCid_injective`, `Kant.Dasl.mkCid_lt` — the `0xDA51` bit layout is a faithful, injective, in-range encoding.
- `Kant.Dasl.monsterOrder_eq` — the product of the Monster prime powers is the Monster group order.
- `Kant.Dasl.rotate71_add/period/inverse` (and the `reflect59`, `dual47` analogues, plus the three commutation lemmas) — the orbifold symmetries form a commuting ℤ/71 × ℤ/59 × ℤ/47 action.
- `Kant.Dasl.mergeCids_comm/assoc/self/unit`, `Kant.Dasl.mergeAll_perm` — merging peer address sets is order-independent.

**Documents**

- `Kant.Erdfa.escape_unescape_id`, `escape_injective`, `escape_no_markup` — escaping is lossless and cannot emit markup.
- `Kant.Store.get_witness`, `get_put_eq`, `put_idem`, `get_put_of_ne`, `has_put_mono`, `put_comm_lookup` — the content-addressed store behaves like a map keyed by witness, and insertions commute.
- `Kant.Sheaf.daslType_roundTrip`, `fromName_name`, `prime_injective`, `section_card` — the sheaf taxonomy is a bijective labelling with 320 sections.

**Transport**

- `Kant.Sneakernet.chunk_flatten` — chunking loses nothing.
- `Kant.Sneakernet.chunk_length_le`, `frames_fit_social` — every frame fits the channel, and social exports stay under 5 MB.
- `Kant.Sneakernet.reassemble_frames`, `reassemble_perm`, `reassemble_frames_perm` — frames reassemble to the original payload regardless of arrival order.

**Covert channels**

- `Kant.Stego.extract_embed`, `extractBlob_embedBlob` — hidden payloads come back out exactly.
- `Kant.Stego.embed_preserves_high_bits`, `embed_lt_256` — embedding only touches the low bit, so the carrier stays a valid 8-bit sample.

**Network**

- `Kant.Sync.sync_preserves`, `sync_delivers`, `sync_idem`, `has_sync_iff` — sync adds exactly the remote pastes and nothing else, and is idempotent.
- `Kant.Sync.get_sync_iff`, `sync_converges` — collision-free peers converge to the same store no matter which side syncs first.

**Credits**

- `Kant.Credits.Ledger.serve_balance`, `serve_valid`, `totalEarned_serve` — serving bytes credits exactly the server.
- `Kant.Credits.Ledger.spend_eq_none_iff`, `spend_balance`, `spend_valid` — spending fails exactly when the balance is short, and never goes negative.
- `Kant.Credits.Ledger.earned_le_total`, `balance_le_totalEarned` — no credit is created out of nothing.

**Code movies**

- `Kant.CodeMovie.rleDecode_rleEncode`, `rleEncode_length` — compression round-trips.
- `Kant.CodeMovie.ungodel_godel`, `godel_injective`, `unmovie_movieGodel` — a whole movie is a single Gödel number you can recover it from.
- `Kant.CodeMovie.frameAt_periodic` — playback loops.
- `Kant.CodeMovie.Circuit.decodeCircuit_encodeCircuit`, `encode_injective` — circuits survive the same numeric encoding.

**The feed**

- `Kant.Feed.view_resolves` — every row on screen is a post the store really holds, at the address the row shows.
- `Kant.Feed.row_title_recoverable`, `row_body_recoverable`, `row_no_markup` — rows are lossless and cannot inject markup.
- `Kant.Feed.mem_search_iff` — search returns exactly the posts containing the phrase.
- `Kant.Feed.paginate_flatten`, `paginate_length_le`, `paginate_length_pos` — paging shows each post exactly once, no page over the page size, no empty pages.
- `Kant.Feed.thread_sound`, `mem_replies_iff`, `root_mem_thread` — a thread is its root plus precisely its replies.
- `Kant.Feed.newest_perm`, `newest_sorted` — ordering neither adds nor drops a post and really is ordered.

**Copy and paste**

- `Kant.Clipboard.Envelope.decode_encode` — copy then paste is the identity.
- `Kant.Clipboard.pasteText_copyText`, `Kant.Feed.row_copy_roundTrip` — a copied post pastes back as that post.
- `Kant.Clipboard.toPaste_eq_none_of_mismatch`, `pasteText_eq_none_of_mismatch` — content that disagrees with its witness is refused.
- `Kant.Clipboard.pasteReceipt_copyReceipt_of_paste` — the results (address, size, credits) copy and paste back exactly.
- `Kant.Clipboard.pasteAll_copyAll` — a whole page copies as one bundle and pastes back post for post.
- `Kant.Clipboard.parseShareUrl_shareUrl`, `shareUrl_paste_roundTrip` — a share link carries the whole result.

**Memes with embedded data**

- `Kant.Meme.decode_render` — what is embedded comes back out, without the finder knowing the payload length.
- `Kant.Meme.roundTrip_paste`, `roundTrip_receipt`, `roundTrip_pastes` — a post, its results, or a whole page shared as a meme are recovered exactly.
- `Kant.Meme.render_length`, `render_valid`, `render_preserves_high_bits`, `fits_social` — the meme is the same size and the same picture, and stays within the 5 MB cap.
- `Kant.Meme.caption_no_markup`, `caption_recoverable`, `witness_infix_caption` — the visible caption is safe in a page, readable back, and shows the address.

**Quote reposts and share cards**

- `Kant.Repost.pasteQuote_copyQuote`, `quoted_original` — a quote copies out and pastes back as the same remark on the same original.
- `Kant.Repost.pasteQuote_eq_none_of_bad_original` — a doctored quotation is refused outright, so no one can be quoted saying something they did not post.
- `Kant.Repost.roundTrip_quote` — a quote shared as one picture comes back as the same quote.
- `Kant.Repost.readCard_card`, `pasteCard_postCard`, `pasteCard_receiptCard`, `pasteCard_bundleCard` — a card's visible headline and its embedded data travel together; the post, the results or the whole page come back from the card alone.
- `Kant.Repost.postCard_headline_no_markup`, `headline_recoverable`, `card_shows_address` — the headline is safe in a page, readable back, and always shows the address.

**Strips of pictures**

- `Kant.Strip.readStrip_strip` — a share cut across several stills reads back as the envelope it was made from.
- `Kant.Strip.readStrip_perm` — the stills may be posted, downloaded and collected in any order.
- `Kant.Strip.roundTrip_post`, `roundTrip_pastes`, `roundTrip_quote_strip` — a post, a whole page or a quote shipped as a strip comes back exactly.
- `Kant.Strip.strip_length`, `strip_still_length`, `strip_fits_social`, `strip_valid` — each still is the size of the template, a valid picture, and within the 5 MB cap.

**Finding other clients**

- `Kant.Rendezvous.roomOf` / `Kant.Rendezvous.scan_same_room` — everyone who scans the same chat code computes the same room name, and the room name is a digest, so the code never travels with the room secret in the clear.
- `Kant.Rendezvous.pasteInvite_copyInvite`, `parseInviteUrl_inviteUrl` — a chat code, as text or as a link, reads back as the invitation it was made from.
- `Kant.Rendezvous.invite_fits_qr` — an invitation fits in a QR code.
- `Kant.Rendezvous.parseAnnounce_printAnnounce` — a peer announcement round-trips over the wire.
- `Kant.Rendezvous.Roster.mem_merge_iff`, `merge_perm`, `merge_idem` — you learn exactly the peers you were told about, in any order, and hearing the same gossip twice changes nothing.
- `Kant.Rendezvous.discovery_transitive`, `meet_knows` — if A knows B and B knows C then after one exchange A knows C; two strangers that scan the same code end up knowing each other.
- `Kant.Rendezvous.best_spec`, `best_congr` — clients that heard the same announcements dial the same address for a peer.

**The relay and chat**

- `Kant.Relay.Server.lines_post`, `post_prefix`, `fetch_since`, `poll_lossless` — the relay is an append-only log per room: posting adds one line to one room, and polling from the cursor you were last given returns exactly what was posted since, with nothing lost.
- `Kant.Relay.parseMsg_printMsg` — a chat message round-trips through the relay.
- `Kant.Relay.parseMsg_eq_none_of_mismatch`, `relay_cannot_forge` — a line whose witness does not match its content is refused, so a relay can drop messages but cannot edit or invent them.
- `Kant.Relay.mem_receive_iff`, `receive_perm`, `transcript_perm`, `clients_agree` — two clients handed the same messages by any route, in any order, show the same transcript.
- `Kant.Relay.discover_via_relay` — a client that announces itself into a room is found by everyone who polls that room afterwards.

**End to end**

- `Kant.Pipeline.pipeline_roundTrip` — paste → witness → frames → LSB-stego carrier → recovered paste is the identity.
- `Kant.Pipeline.pipeline_witness` — the recovered paste has the witness it was addressed by.
- `Kant.Pipeline.publish_social_fits`, `carrier_capacity_needed` — published carriers respect the 5 MB limit and the stated capacity bound.

The feed, the copy/paste envelope, the meme container, quote reposts, share
cards and picture strips are specified in
[`docs/FEED-CLIPBOARD-MEMES.md`](docs/FEED-CLIPBOARD-MEMES.md).

## Browser client (`web/`)

`web/kantzk.mjs` is a direct transcription of the Lean definitions (BigInt where
Lean uses `Nat`). `web/test.mjs` pins it to golden values computed by Lean —
run it with `node web/test.mjs`.

`web/index.html` is the client. It lets you

- paste text or fetch a URL, and address it by DASL CID + witness;
- pin it locally (Cache Storage via `web/sw.js`) so it gets a servable `/pin/<witness>` URL, and earn ledger credits when the service worker serves it;
- frame it for any channel and check the 5 MB social cap;
- hide a paste in a PNG via canvas LSB stego, or export SVG / animated-GIF-style frames;
- record a ≤ 5 MB WebM social export with `MediaRecorder`;
- read a paste aloud with `speechSynthesis` (TTS);
- play a code movie back through WebGL;
- **see the posts**: a feed of every post held, newest first, with live search, paging, threads and per-post credits;
- **copy and paste the results**: one-click copy of a post, of its results (address, size, credits), of a share link, or of the whole page as one bundle — and a box to paste any of those back in, which refuses anything whose content does not match the witness travelling with it;
- **share as a meme with the data inside**: draw a meme from a built-in or uploaded template, hide the post (or its results, or the whole page) in the picture's least significant bits, and export a PNG within the 5 MB social cap — then read any such meme back and have its posts appear in the feed;
- **quote and repost**: quote any post with a remark of your own, as text or as one picture — the quote carries the original whole, and a doctored quotation is refused when it is pasted back;
- **share cards**: copy a readable headline plus a link whose fragment carries the post, the results or the whole page, ready to drop into any chat window or social feed;
- **strips of stills**: when a share is too big for one picture, export it as a numbered set of PNGs — drop any collection of them back in, in any order, and the share is reassembled;
- **find other clients and chat**: open or join a room, show the room's **chat QR code** (drawn by `web/kant-qr.mjs`, no dependencies) or copy it as text or a link, scan someone else's code with the camera, watch the peer list fill in, and talk — over a relay, over WebRTC once the relay has introduced you, or over `BroadcastChannel` between tabs of the same browser.

`web/kant-net.mjs` is the transcription of `Kant.Rendezvous` and `Kant.Relay`
plus the transports; `web/kant-qr.mjs` is a self-contained QR encoder for the
chat code. See [`docs/DISCOVERY-AND-CHAT.md`](docs/DISCOVERY-AND-CHAT.md).

Everything in `web/` and `server/` is *unverified*: it is checked only by the
test scripts (`web/test.mjs`, `web/wasm-test.mjs`, `web/net-test.mjs`,
`web/qr-test.mjs`), not by proof.

## WASM

`dist/kant_kernel.wasm` is a real WebAssembly binary extracted **from Lean
itself**: its bytes are computed by a verified encoder
(`RequestProject/Wasm/`), not by a C toolchain, so no emscripten or WASI SDK is
involved.

```
lake exe emitwasm dist    # writes dist/kant_kernel.wasm and dist/kernel-vectors.json
node web/wasm-test.mjs    # WebAssembly.validate + run + cross-check
```

Twenty-one `i64` functions are exported (hex digits, the FNV-1a digest round
and offset basis, big-endian byte expansion, DASL address arithmetic and the
merge algebra, serve credits, stego LSB write/read, the orbifold action, Cantor
pairing, the 5 MB social bound). For each one there is a theorem that the wasm code
computes the corresponding `Kant.*` definition, on top of a LEB128 round-trip
proof and a compiler-correctness theorem for the instruction fragment. The
design follows [`argumentcomputer/Wasm.lean`](https://github.com/argumentcomputer/Wasm.lean),
re-derived for the current toolchain and proved. See
[`docs/WASM-EXTRACTION.md`](docs/WASM-EXTRACTION.md).

The fragment has no linear memory or loops, so the list- and string-processing
definitions (`witness`, `frames`, `embedBlob`, `godel`, …) are not exported
directly; `web/kant-wasm.mjs` obtains `fnv1a`, `hexEncode`, `digest` and
`witness` by folding the verified per-step exports instead. `web/index.html`
loads the kernel on start-up and recomputes each paste's witness inside
WebAssembly, falling back to the JavaScript core if the binary is not served.

## Networking

### Clients finding each other, and chat

There is a running peer service in this repository: `server/`. Two ways to run
it, one protocol:

```
node server/relay.mjs --port 8787 --static web   # your Linux box; zero dependencies
cd server && npx wrangler deploy                 # Cloudflare Worker + one Durable Object per room
```

A **room** is named by the digest of a secret that never leaves the people who
have the chat code, so the relay stores lines under an opaque name. The chat QR
code carries the relay URL, that secret and the inviter's address; scanning it
puts you in the same room, where you announce yourself, learn everyone else, and
talk. Messages are self-certifying, so the relay cannot edit them — but the
relay does see them, since line contents are not yet encrypted. The full
walkthrough, protocol, systemd unit, nginx snippet and Cloudflare instructions
are in [`docs/DISCOVERY-AND-CHAT.md`](docs/DISCOVERY-AND-CHAT.md) and
[`server/README.md`](server/README.md).

### The other transports

See [`docs/WASM-AND-NETWORK.md`](docs/WASM-AND-NETWORK.md). Short version: the
Lean → C → WebAssembly path (an alternative to the extraction above, which
would cover the whole port) and the IPFS / iroh / libp2p / torrent /
archive.org integration are specified and scripted there, but not implemented
as running services here (the relay above is the only peer service in the
repository), and the emscripten toolchain that path needs is not present in the
build environment used here.
