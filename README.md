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
node web/uucp-test.mjs    # 28 checks of the relay-free sneakernet (bags, tweets, bang paths, static pages)
node web/site-test.mjs    # 47 checks of the configuration file, the whole-URL codes and the share card
node web/flow-test.mjs    # 85 checks of the guided flow: dressed invite codes, tolerant joining, screens, plain-text copy
node web/join-test.mjs    # 14 checks of the cross-device join: two clients, one real relay, no shared browser
node web/page-test.mjs    # 75 checks driving web/index.html itself in a minimal DOM
node web/sharelog-test.mjs   # 64 checks of sharing the log, posting it to the store, carrying blocks by hand
node web/handpage-test.mjs   # 32 checks driving web/hand.html — the no-server, chat-only mode
node scripts/invite-card.mjs '<code or link>'        # a scannable invite card: link + icon + caption, as SVG
node scripts/sneakernet.mjs init site --name alice   # a static sneakernet site: no server to run
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
| new (sneakernet) | `RequestProject/Kant/Uucp.lean` | the relay-free static sneakernet: mailbags carried by DM, tweet thread, QR code or link; bang-path store and forward; the static site and its snapshot staleness |
| new (site/card) | `RequestProject/Kant/SiteCard.lean` | the deployment configuration file, the whole page URL every code and link carries, and the share card (URL + text + picture) shared in chat |
| new (invite card) | `RequestProject/Kant/InviteCard.lean` | the invite code carries the whole link, with a custom icon drawn on it and a custom line of text under it |
| new (joining) | `RequestProject/Kant/Join.lean` | finding the invitation in a pasted message however it arrives — in a sentence, in brackets, with a full stop or a newline after it |
| new (onboarding) | `RequestProject/Kant/Onboarding.lean` | the screens, the camera switch, and the guided first run with its spoken prompts |
| new (plain text) | `RequestProject/Kant/PlainText.lean` | copying a post as the text a human reads, with its title, link, address and time optional and separable |
| new (connecting) | `RequestProject/Kant/Connectivity.lean` | which relay a client actually uses, when two clients are linked, and the verdict when they are not |
| new (which code is this) | `RequestProject/Kant/CardDebug.lean` | what a pasted code is — a card, an invitation or a page link — and why two cards can never connect |
| new (diagnostics) | `RequestProject/Kant/Diagnostics.lean` | the net/error log: bounded, ordered, readable back, and shareable with no secret in it |
| new (sharing the log) | `RequestProject/Kant/ShareLog.lean` | the run handed over as text, as a post in the store, or as numbered chat messages — with no secret in any of them |
| new (no server) | `RequestProject/Kant/Handoff.lean` | the numbered steps two people follow in a chat, the proof that none of them needs a server, and carrying a block by hand |
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
- `Kant.Uucp.openBag_packBag` — a mailbag copied into a DM, a tweet, a QR code or a link pastes back as exactly the same messages.
- `Kant.Uucp.Node.mem_sneakernet_iff`, `Node.paste_bad` — a node holds exactly what it held plus what the codes it pasted carried: **you are as up to date as the last code you pasted**, and an unreadable code changes nothing.
- `Kant.Uucp.Node.paste_perm`, `paste_idem`, `paste_monotone` — pastes commute, repeat harmlessly and never lose anything, so bags may travel by any route in any order.
- `Kant.Uucp.bag_rejects_forgery` — a bag with one doctored line does not open at all: a courier can drop mail but never invent it.
- `Kant.Uucp.bag_canonical` — two nodes that know the same lines hand out byte-identical codes.
- `Kant.Uucp.handoff`, `exchange_agree`, `uucp_path`, `uucp_route` — one bag catches you up with the sender; two bags, one each way, leave both sides displaying the same transcript; and a bag carried a!c!b along a bang path delivers just the same.
- `Kant.Uucp.sneakernet_matches_relay` — what a node displays after pasting a bag is exactly what a relay client displays after being handed the same messages: the relay is redundant, not merely optional.
- `Kant.Uucp.thread_fits_tweet`, `readThread_thread`, `readThread_perm` — a bag too big for one tweet goes out as numbered parts, each inside the 280-character limit, collected in any order.
- `Kant.Uucp.relay_keeps_current`, `stale_without_paste` — the one exception: connected to a relay you are current without pasting anything; disconnected and pasting nothing, your view does not change at all.
- `Kant.SiteCard.parseConfig_renderConfig` — the deployment configuration file (`kant.config`: origin, caption, picture, description) is written and read back unchanged; a line without an `=` is a comment.
- `Kant.SiteCard.pasteUrl_length`, `pasteUrl_address`, `urlAddress_addressUrl` — a page URL is the configured origin, a `#`, and the 64-hex address of the content, and the address comes back out of it.
- `Kant.SiteCard.qrPayload_origin_prefix`, `parseQrPayload_qrPayload`, `pasteUrl_fits_qr` — a code carries the **whole URL**: an ordinary scanner gets an openable link, this client still recovers the exact payload, and the URL fits in one code.
- `Kant.SiteCard.readCard_cardSvg`, `cardSvg_caption_visible`, `cardSvg_picture_used`, `cardSvg_url_visible` — a share card exported as a picture, caption and logo included, reads back as the same card, and the text, picture and URL really appear in it.
- `Kant.SiteCard.card_text_no_markup`, `cardSvg_caption_recoverable` — no caption, URL or picture reference can break out of its element, and the caption recovers exactly.
- `Kant.SiteCard.logo_area_bound` — the picture in the middle of the code covers at most a twenty-fifth of its modules, well inside the error-correction budget.
- `Kant.SiteCard.readChatCard_chatMsg`, `readChatText_chatText`, `chatMsg_tamper` — a card shared in a room arrives as the same card, a card pasted as plain text into any chat comes back whole, and a doctored line is refused rather than shown as somebody else's card.
- `Kant.InviteCard.inviteUrl_origin_prefix`, `inviteUrl_not_bare`, `parseInviteUrl_inviteUrl`, `inviteUrl_fits_qr` — the invite code carries the whole page link rather than the bare `kzinvite:…` payload, so any camera app offers an openable link; it still reads back as exactly the invitation, and it still fits in one code.
- `Kant.InviteCard.inviteCardSvg_icon_used`, `inviteCardSvg_caption_visible`, `inviteCardSvg_url_visible`, `inviteCard_icon_area_bound`, `inviteCard_no_markup`, `inviteCardSvg_roundTrip` — the custom icon is drawn on the code, the custom words are printed under it, the link is printed too, the icon stays inside the error-correction budget, nothing typed can break out of its element, and the exported picture reads back whole.
- `Kant.Join.findInvite_inviteUrl`, `findInvite_copyInvite`, `findInvite_in_message`, `findInvite_trailing_newline`, `wordInvite_junk`, `message_same_room` — a link pasted with any junk around it joins, a bare code still joins, a word that is not a code is never mistaken for one, and both sides land in the same room.
- `Kant.Onboarding.camera_implies_scan` — in every state the interface can reach, a running camera means the scan screen is the one on show: the off button is always in front of the user. With `camera_off_after_stop`/`_back`/`_leave`/`_goto`/`_join`, `back_goes_home` and `screen_reachable`.
- `Kant.Onboarding.qrText_eq_shareText`, `share_then_join`, `join_lands_in_room` — there is one thing to share, not two; what one side shows the other side accepts; and following it puts you in the room, on the chat screen, with the camera off.
- `Kant.Onboarding.first_run_completes`, `join_run_completes`, `nextTask_eq_none_iff`, `step_progress_mono`, `hushed_says_nothing`, `promptFor_ne_empty` — both scripted first runs finish, the guide stops exactly when everything is done, a task once done stays done, and the voice really is silent when hushed.
- `Kant.PlainText.copyPlain_eq_content`, `copyPlain_ne_copyText`, `bodyOf_copyPlainWithMeta`, `metaOf_copyPlainWithMeta`, `copyPlainWithMeta_link_visible` — copying a post gives the characters that were typed rather than an encoding of them; with the details attached, the text and the four details are both recoverable, and the whole page link really is printed in the footer.
- `Kant.Uucp.Site.serve_static`, `visitor_catches_up`, `snapshot_is_stale` — the static server has no state to lose, a visitor who pastes the page catches up with the publisher, and a line written after publication stays invisible until a fresher code is pasted.

**Connecting, and saying why not**

- `Kant.Connectivity.effectiveRelay_configured`, `effectiveRelay_selfHosted`, `effectiveRelay_needs_probe` — a configured relay that answers wins; with none configured, the origin that served the page is used if it really answers as a relay; an origin that has not answered a probe is never used.
- `Kant.Connectivity.two_browsers_one_machine_linked`, `two_browsers_one_machine_stuck`, `same_browser_linked`, `Linked.symm` — two browsers on one machine are linked exactly when a relay joins them, tabs of one browser need nothing, and being linked is symmetric.
- `Kant.Connectivity.diagnose_eq_ok_iff`, `diagnose_noRoom`, `diagnose_roomMismatch`, `diagnose_relayDown`, `diagnose_two_browsers_no_relay`, `explain_ne_nil`, `explain_injective` — the verdict is `ok` exactly when the two clients can talk, each failure gets its own verdict, and the six explanations are six different sentences.
- `Kant.CardDebug.card_no_room`, `page_no_room`, `pair_not_connectable_of_card_left`, `pair_not_connectable_of_card_right`, `pair_not_connectable_of_page_left` — a share card and a page link name no room, so pairing either with anything is never `connectable`.
- `Kant.CardDebug.pair_connectable_iff`, `connectable_linked`, `configured_relay_links`, `static_deployment_stuck` — two codes connect exactly when both are invitations to one room through one non-empty relay; such a pair really does link two clients; a reachable `relay =` links them wherever the page is hosted, and a blank one on a static origin provably cannot.
- `Kant.CardDebug.userCard_classify`, `userCard_no_room`, `userCard_pair`, `userCard_not_connectable`, `userPageLink_classify`, `userCard_warnings` — the reported text, classified: one share card (not two), naming no room, with a relative picture reference.
- `Kant.CardDebug.explain_ne_nil`, `explain_injective` — six outcomes, six different sentences.
- `Kant.Diagnostics.parseEvent_printEvent`, `parseLog_renderLog`, `parseHeader_header`, `parseReport_renderReport` — an event, a whole log and a whole shared report are written out as text and read back unchanged.
- `Kant.Diagnostics.Log.add_length_le`, `Log.add_getLast`, `Log.add_total`, `Log.Wf.record` — the log is bounded, drops the oldest rather than the newest, and counts honestly what it dropped.
- `Kant.Diagnostics.share_no_secret`, `share_clean`, `share_keeps`, `report_events_clean`, `ref_length`, `ref_ne` — a shared run quotes no room secret, keeps everything else, and names rooms by an eight-character handle.

- `Kant.ShareLog.shared_no_secret`, `shareReport_room_ne`, `shared_keeps`, `posted_no_secret`, `chat_no_secret` — a shared run carries no secret and no room, only an eight-character handle, and withholds nothing else; the same holds of what the store holds and of what arrives through a chat.
- `Kant.ShareLog.postLog_resolves`, `postLog_idem`, `postLog_monotone`, `postLog_in_feed`, `logPaste_content_roundTrip`, `logPaste_witness_congr` — posting the run to the store gives it an address that resolves, twice is a no-op, nothing already held is lost, it appears in the feed, it parses back, and two people with the same run post the same block.
- `Kant.ShareLog.readChatParts_chatParts`, `readChatParts_perm`, `chatParts_fit_tweet`, `isAscii_logText` — the run cut into chat messages arrives intact, in any order, with every message inside a tweet and every character plain ASCII.
- `Kant.Handoff.script_serverless`, `serverless_all`, `codes_script_isAscii` — no step of any script the app can show needs a server, and everything it asks you to send is plain text.
- `Kant.Handoff.run_delivers`, `run_delivers_back`, `run_keeps`, `run_agree`, `run_after_write_new` — four copy-pastes and both sides display the same conversation; saying something new and repeating them delivers it.
- `Kant.Handoff.carry_resolves`, `carry_agrees`, `carry_idem`, `carry_monotone`, `logScript_delivers` — a block, or a whole run, copied into a chat and pasted on the other side lands under exactly the address it left with.

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

`web/index.html` is the **simple client**: six screens, one link to share, one
code to show, a guide that talks you through the first run, and a camera that
can always be switched off. Its design — with the use-case and sequence
diagrams, and the theorem behind each promise — is
[`docs/UX-FLOW.md`](docs/UX-FLOW.md).

- **one link, one code.** The invite code carries the whole page link
  (`https://<origin>/#kzinvite…`), not the bare `kzinvite:…` payload, so any
  camera app offers to open it. Around it is a card: your own words printed
  under the code and your own picture drawn in the middle of it, both editable
  on the share screen, and the link printed underneath for a human to read.
- **joining is forgiving.** Paste the whole message your friend sent — the link
  in a sentence, in brackets, with a full stop after it, with a trailing
  newline — and it still joins.
- **the camera is always stoppable.** A red **Stop the camera** button, and the
  camera also goes off on back, on leave, on tapping any other screen and on a
  code being read. That the camera can never run behind another screen is
  proved, not tested.
- **the guide talks.** Three tasks, spoken aloud and printed, with a mute
  button that really does silence it.
- **copying gives you the words.** Copy a note as plain text, or as plain text
  with its title, link, address and time under a `-- ` line.
- **it says when it cannot reach anybody.** The relay is named in
  `web/kant.config` and probed on startup; with none configured the client
  asks the origin that served the page whether it is itself a relay, and if
  it is not, the first screen says that only tabs of this browser will find
  each other, instead of failing silently.
- **it keeps a log, and shares it.** Every probe, request, socket, channel
  and uncaught error goes into one bounded run log. **More → Diagnostics**
  shows the verdict and a live tail; [`web/diag.html`](web/diag.html) shows
  the whole run, re-runs the checks, and copies, saves or links it with the
  room secret and the invite withheld. See
  [`docs/DIAGNOSTICS.md`](docs/DIAGNOSTICS.md).
- **it says what a pasted code *is*.** `diag.html` → **What is this code?**
  takes one code or two — a whole share card, a bare `kzcard:` / `kzinvite:`
  line, or a page link — and says what each one is, whether the two can
  connect, and what to do instead. `node scripts/kant-debug.mjs` does the
  same from a terminal, and `--probe` checks whether the deployment has any
  meeting point at all. See [`docs/CARD-DEBUG.md`](docs/CARD-DEBUG.md).

`web/lab.html` is the **workbench** — the whole control panel, reachable from
**More → Open the workbench**. It lets you

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
- **keep going with no relay at all**: write lines offline, copy your whole spool as one mailbag for a DM, as a link, as a QR code or as a numbered tweet thread; paste anybody's bag, link or thread back in (a doctored one is refused whole); the spool survives reloads, and the page is exactly as fresh as the last code pasted into it;
- **share the whole URL, with your text and your picture**: every code, link and card carries `https://<origin>/#<address>`, with the origin read from `web/kant.config`; section 9 builds a **share card** — the code with a caption under it and a picture in the middle — that you can show, copy, download as SVG or PNG, hand to the system share sheet, or send straight into the chat room, and read back from a pasted card, a link or a dropped `.svg`;
- **find other clients and chat**: open or join a room, show the room's **chat QR code** (drawn by `web/kant-qr.mjs`, no dependencies) or copy it as text or a link, scan someone else's code with the camera, watch the peer list fill in, and talk — over a relay, over WebRTC once the relay has introduced you, or over `BroadcastChannel` between tabs of the same browser.

`web/kant-flow.mjs` is the transcription of `Kant.Join`, `Kant.Onboarding`,
`Kant.InviteCard` and `Kant.PlainText` — the guided flow the simple client is
built out of.
`web/kant-net.mjs` is the transcription of `Kant.Rendezvous` and `Kant.Relay`
plus the transports; `web/kant-uucp.mjs` is the transcription of `Kant.Uucp`,
the relay-free sneakernet; `web/kant-site.mjs` is the transcription of
`Kant.SiteCard`, the configuration file, the full-URL codes and the share card;
`web/kant-diag.mjs` is the transcription of `Kant.Connectivity` and
`Kant.Diagnostics` — the relay decision, the verdicts, the run log and the
shareable report;
`web/kant-carddebug.mjs` is the transcription of `Kant.CardDebug` — which of
the three codes a pasted block is, and what two of them do together;
`web/kant-qr.mjs` is a self-contained QR encoder for the chat code, the mailbag
and the card. See [`docs/DISCOVERY-AND-CHAT.md`](docs/DISCOVERY-AND-CHAT.md),
[`docs/STATIC-SNEAKERNET.md`](docs/STATIC-SNEAKERNET.md) and
[`docs/SITE-CARD.md`](docs/SITE-CARD.md).

Where the codes point is configuration, not code: `web/kant.config` names the
`origin` (`https://kant.cicada71.net/` by default), the caption and the picture
of the share card, and the `relay` two different devices should meet through
(empty by default — see [`server/README.md`](server/README.md) for how to put
one up). Edit that file — or pass `--config` / `--base` to
`scripts/sneakernet.mjs publish` — to point a deployment somewhere else.

Everything in `web/` and `server/` is *unverified*: it is checked only by the
test scripts (`web/test.mjs`, `web/wasm-test.mjs`, `web/net-test.mjs`,
`web/qr-test.mjs`, `web/uucp-test.mjs`, `web/site-test.mjs`,
`web/flow-test.mjs`, `web/join-test.mjs`, `web/page-test.mjs`,
`web/diag-test.mjs`, `web/diagpage-test.mjs`, `web/carddebug-test.mjs`,
`web/sharelog-test.mjs`, `web/handpage-test.mjs`), not by proof.

### Sharing the log, and running with no server at all

**Share the log** (under *More → Diagnostics*, and on `web/diag.html`) hands the
run over as text, as numbered chat messages each inside a tweet, or — with
**Post the log to the store** — as an ordinary content-addressed post with a
witness and a link. A shared run never quotes a secret and never carries the
room, only its eight-character handle.

`web/hand.html` is the same system with the network removed: two people, any
chat window, four copy-pastes, and both sides hold the same conversation. The
steps, the guarantee that none of them needs a server, and the rules for
carrying a block or a run by hand are proved in
`RequestProject/Kant/ShareLog.lean` and `RequestProject/Kant/Handoff.lean`, and
written up in [`docs/SHARE-LOG-AND-MANUAL-CHAT.md`](docs/SHARE-LOG-AND-MANUAL-CHAT.md).

## WASM

`dist/kant_kernel.wasm` is a real WebAssembly binary extracted **from Lean
itself**: its bytes are computed by a verified encoder
(`RequestProject/Wasm/`), not by a C toolchain, so no emscripten or WASI SDK is
involved.

```
lake exe emitwasm dist        # writes dist/kant_kernel.wasm and dist/kernel-vectors.json
node scripts/embed-kernel.mjs # refreshes web/kant-kernel-embedded.mjs, the fallback copy
node web/wasm-test.mjs        # WebAssembly.validate + run + cross-check + delivery tests
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
WebAssembly.

That the binary is a *valid* module is itself proved, in both the senses an
engine uses: `RequestProject/Wasm/Decode.lean` gives a reader for the binary
format and proves that reading undoes writing (`decodeModule_module`,
`kernelBytes_decodes` — every section size, LEB128 field and opcode parses back
to the module that was encoded, with no trailing bytes), and a stack type
checker with `typecheck_compile` / `kernelBytes_validates` (every exported body
leaves exactly one `i64`, the result type its signature declares).

Delivery is handled separately from validity: the loader tries several
locations, reports the real reason each one failed (`HTTP 404`, `not a wasm
module (…)`) instead of blaming validation, and falls back to
`web/kant-kernel-embedded.mjs`, a base64 copy of the same bytes, so the proved
kernel still runs from `file://`, offline, or on a host that ships only `web/`.
`server/relay.mjs --static web` serves `/dist/kant_kernel.wasm` from the sibling
directory as `application/wasm`.

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

### Two browsers on one machine, and what to do when nothing connects

Two *tabs* of one browser find each other with no server at all. Two
*browsers* — or a window and a private window, or two profiles — share
nothing, so they need a relay even when they are on the same laptop. With
`relay =` left empty in `web/kant.config`, the client now asks the origin it
was served from whether it is itself a relay, so

```
node server/relay.mjs --port 8787 --static web --log relay.log
# open http://localhost:8787/ in two different browsers
```

is enough, with no configuration. A configured relay that answers always
wins; an origin that has not answered a probe is never used. The rule and
its proofs are `effectiveRelay` in
[`RequestProject/Kant/Connectivity.lean`](RequestProject/Kant/Connectivity.lean).

Every transport step is written into one bounded log — the config, the
probes, each relay request with its status, socket open/close/error, the
same-browser channel, every ICE and data-channel state, and uncaught page
errors. Nothing is swallowed. The "more" screen shows the verdict and a
live tail, and [`web/diag.html`](web/diag.html) shows the whole run, runs
the checks again on demand, and copies, saves or links it — with the room
secret and the invite withheld, which is proved rather than asserted. The
log, the verdicts and the relay's `--log` are described in
[`docs/DIAGNOSTICS.md`](docs/DIAGNOSTICS.md); the model is
[`RequestProject/Kant/Diagnostics.lean`](RequestProject/Kant/Diagnostics.lean).

Codes are not interchangeable, and the difference is the usual reason two
people cannot connect: a **share card** (`kzcard:`) and a **page link**
(`<origin>#<64 hex>`) name a page and carry no room, while only an
**invitation** (`kzinvite:`) carries the relay and the secret whose digest is
the room. Paste either into *What is this code?* on
[`web/diag.html`](web/diag.html), or run `node scripts/kant-debug.mjs`, and
it will say which you are holding. The rules are proved in
[`RequestProject/Kant/CardDebug.lean`](RequestProject/Kant/CardDebug.lean) and
worked through in [`docs/CARD-DEBUG.md`](docs/CARD-DEBUG.md).

### No relay: the static sneakernet

The relay is now optional. In sneakernet mode nothing runs: your lines live in
a spool in the browser (or in a directory on disk), and the whole spool copies
out as one **mailbag** — a single line of ASCII that fits in a direct message,
a QR code or a link, and that is cut into a numbered tweet thread when it does
not. Whoever pastes it is caught up to the moment it was made, and nothing
else ever reaches them. A courier can drop your mail but cannot forge it, and
store-and-forward along a UUCP bang path `a!c!b` works exactly as it used to.

```
node scripts/sneakernet.mjs init    site --name alice
node scripts/sneakernet.mjs write   site "something to say"
node scripts/sneakernet.mjs publish site --base https://alice.example/s/
# copy site/ to any static host, object store, pinned directory or USB stick
node scripts/sneakernet.mjs paste   site bag.txt     # what somebody DM'd you
```

`publish` emits `bag.txt`, `thread.txt`, `link.txt`, `qr/*.svg` and an
`index.html` that shows all of them: static files only, no API and nothing to
keep running. The Lean model — including the proof that this displays exactly
what a relay would have shown you, and the proof that a published page is a
snapshot that goes stale until you paste a fresher code — is in
[`docs/STATIC-SNEAKERNET.md`](docs/STATIC-SNEAKERNET.md).

### The other transports

See [`docs/WASM-AND-NETWORK.md`](docs/WASM-AND-NETWORK.md). Short version: the
Lean → C → WebAssembly path (an alternative to the extraction above, which
would cover the whole port) and the IPFS / iroh / libp2p / torrent /
archive.org integration are specified and scripted there, but not implemented
as running services here (the relay above is the only peer service in the
repository), and the emscripten toolchain that path needs is not present in the
build environment used here.
