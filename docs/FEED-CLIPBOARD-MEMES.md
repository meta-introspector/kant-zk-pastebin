# Seeing the posts, copying the results, sharing them as memes

Three layers were added on top of the content-addressed core.  Each is
defined in Lean and its guarantees are proved there; `web/kantzk.mjs` is
an unverified transcription pinned to Lean-computed golden vectors by
`node web/test.mjs`.

| layer | Lean module | browser |
|---|---|---|
| the feed | `RequestProject/Kant/Feed.lean` | section 4 of `web/index.html` |
| copy / paste / share links | `RequestProject/Kant/Clipboard.lean` | section 5 |
| memes with embedded data | `RequestProject/Kant/Meme.lean` | section 6 |

## 1. The feed

`Kant.Feed.view` renders the store as rows.  A row carries the witness,
the DASL address, the escaped title and body, the timestamp, the thread
parent, the byte size, and the clipboard text that reproduces the post.

* `view_resolves` — every row comes from a post the store answers to, at
  the address the row advertises.
* `row_title_recoverable`, `row_body_recoverable` — nothing is lost in
  rendering; `row_no_markup` — nothing can escape its element.
* `search` is `filter` by substring: `mem_search_iff` says a post is in
  the results exactly when it is in the feed and the phrase occurs, as a
  contiguous phrase, in its title or body.
* `paginate` cuts the feed into pages: `paginate_flatten` (every post
  shown exactly once), `paginate_length_le` (no page over the page size),
  `paginate_length_pos` (no empty pages).
* `thread root ps` is the root followed by its direct replies:
  `thread_sound`, `mem_replies_iff`, `root_mem_thread`.
* `newest` sorts by the digits of the timestamp: `newest_perm` (a
  permutation) and `newest_sorted` (really ordered).

## 2. The clipboard envelope

An envelope is a tag plus byte fields.  On the wire:

```
<tag-hex> ":" <field-hex> ":" <field-hex> …
```

Every field is lowercase hex, so a colon can never occur inside one and
the framing is unambiguous (`Kant.Text.splitFields_joinFields`).  The
whole line is printable ASCII with no NUL
(`Envelope.isAscii_encode`, `Envelope.encode_pos`).

| tag | ASCII | fields |
|---|---|---|
| post | `kzpaste` | id, title, content, timestamp, thread parent, witness |
| results | `kzresult` | witness, DASL address, byte size, credits |
| bundle | `kzfeed` | one field per post, each the clipboard text of that post |

The thread-parent field is `00` for "no parent", or `01` followed by the
parent's witness.  Numeric fields are minimal big-endian byte strings
(`Kant.Text.natToBytesBE`, inverted by `bytesBEToNat`).

Guarantees:

* `Envelope.decode_encode` — copy then paste is the identity.
* `pasteText_copyText` — a copied post pastes back as that post.
* `toPaste_eq_none_of_mismatch` — **the envelope is self-verifying**: a
  post is accepted only if the witness travelling with it is the witness
  of the content that arrived, so an edited clipboard string is refused
  instead of being trusted.
* `pasteReceipt_copyReceipt_of_paste` — the results copy and paste back
  exactly, numbers included.
* `pasteAll_copyAll` — a whole page copies as one bundle.
* `parseShareUrl_shareUrl` — the same envelope travels as the fragment of
  a URL: `https://host/path#<envelope>`.  Opening such a link in the
  browser client loads the post straight into the feed.

## 3. The meme container

A meme is an ordinary picture whose colour samples carry, in their least
significant bits:

```
"KZM1" <envelope text> 0x00
```

The marker identifies the container, and the zero terminator is
unambiguous because the envelope text never contains a zero byte.  A
finder therefore does not need to be told the payload length: they read
the carrier to its capacity and stop at the first zero
(`Kant.Stego.extractBlob_embedBlob_prefix`, `Kant.Meme.decode_render`).

* `roundTrip_paste`, `roundTrip_receipt`, `roundTrip_pastes` — a post,
  its results, or a whole page shared as a meme are recovered exactly.
* `render_length`, `render_valid`, `render_preserves_high_bits` — the
  meme is the same size and the same picture as the template, up to one
  unit per sample.
* `fits_social` — a template within the 5 MB social cap yields a meme
  within the cap, so it posts anywhere; `frames_fit_social` and
  `post_roundTrip` reuse the sneakernet transport for the file itself.
* `capacity_chars` — a template of `n` samples carries `n/8 - 5`
  characters of envelope.
* `caption_no_markup`, `caption_recoverable`, `witness_infix_caption` —
  the visible caption is safe to put in a page, readable back character
  for character, and always shows the address.

In the browser the carrier is the red, green and blue samples of the
canvas (alpha is left at 255), and the file is exported as PNG, which is
lossless.  A meme that has been re-encoded by a platform that
recompresses images lossily will not decode — that is a property of the
platform, not of the container.

## Quote reposts

A quote is an envelope tagged `kzquote` with exactly two fields: the
clipboard text of the remark, and the clipboard text of the post it
quotes.  Because clipboard text is pure ASCII (`Envelope.isAscii_encode`)
the two nest inside one envelope with no further escaping.

```
kzquote : hex(copyText comment) : hex(copyText original)
```

Reading a quote pastes both halves, so the original is re-checked against
its own witness on the way in.

* `Kant.Repost.pasteQuote_copyQuote`, `quoted_original` — a quote copies
  out and pastes back as the same remark on the same original.
* `Kant.Repost.pasteQuote_eq_none_of_bad_original` — if the quoted half
  does not paste, the whole quote is refused: a quotation cannot be
  doctored and still be read as a quotation.
* `Kant.Repost.roundTrip_quote` — a quote is an ordinary envelope, so it
  goes into the meme container unchanged and comes back out.  A quote
  carries two whole posts, so it needs about four times the pixels of a
  single-post meme.

## Share cards

A card is what gets pasted into a chat window: a line of readable text,
a newline, then a share link.

```
<headline>
<base>#<envelope text>
```

The headline is stripped of `'#'` (`Kant.Repost.sanitize`), so the link's
`'#'` is the first one in the card and the fragment is exactly the
envelope.  For a post the headline is its escaped title and its address,
for results it is the address, for a page it is the number of posts.

* `Kant.Repost.readCard_card` — the visible text and the embedded data
  travel together, for any headline and any `'#'`-free base URL.
* `Kant.Repost.pasteCard_postCard`, `pasteCard_receiptCard`,
  `pasteCard_bundleCard` — the post, the results, or the whole page come
  back from the card alone.
* `Kant.Repost.postCard_headline_no_markup`, `headline_recoverable`,
  `card_shows_address` — the headline is safe to put in a page, readable
  back character for character, and always shows the address.

## Meme strips: one share over several pictures

A picture of `n` colour samples holds about `n/8` characters of envelope,
which is not always enough: a quote carries two whole posts, a page
carries several.  A large share therefore goes out as a *strip*.  The
envelope text is cut into numbered parts by the sneakernet framing of
`Kant.Sneakernet`, and each part becomes its own still — a frame of an
animated GIF, a carousel, a thread of pictures:

```
kzpart : hex(seq) : hex(total) : hex(part of the envelope text)
```

Each still is an ordinary meme, so the reader extracts the parts one by
one and reassembles them by sequence number.

* `Kant.Strip.readStrip_strip` — a strip reads back as the very envelope
  it was made from.
* `Kant.Strip.readStrip_perm` — the stills may be posted, downloaded and
  collected in **any** order; reassembly depends only on which stills
  arrived, not on when.
* `Kant.Strip.roundTrip_post`, `roundTrip_pastes`, `roundTrip_quote_strip`
  — a post, a whole page, or a quote shipped as a strip comes back
  exactly.
* `Kant.Strip.strip_length`, `strip_still_length`, `strip_fits_social`,
  `strip_valid` — how many stills a share takes, and that each still is
  the size of the template, a valid picture, and within the 5 MB cap.

## Running the checks

```
lake build            # Lean: proofs and the #guard-checked demo
node web/test.mjs     # JS transcription against Lean-computed vectors
```

`RequestProject/Kant/Demo.lean` runs the whole path — post, reply,
search, paging, thread, copy, paste, tamper rejection, share link, quote
repost, share card, meme export, meme import and picture strips — as `#guard`s that are checked at build time.
