# The site URL, the configuration file, and the share card

Everything this client hands to somebody else — a QR code, a link, a message in
chat — carries the **whole address of the page**:

```
https://kant.cicada71.net/#ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605
```

The part after the `#` is the content address (the 64-hex witness of the bytes,
or a whole envelope for an invitation or a mailbag).  The part before it is
deployment data, not program data, so it lives in a configuration file.

Specification: [`RequestProject/Kant/SiteCard.lean`](../RequestProject/Kant/SiteCard.lean)
(no `sorry`, standard axioms only).
Browser transcription: [`web/kant-site.mjs`](../web/kant-site.mjs).
Conformance vectors, computed by Lean: [`web/site-test.mjs`](../web/site-test.mjs).

## 1. The configuration file

`web/kant.config`:

```
# where this deployment lives
origin = https://kant.cicada71.net/
caption = kant-zk-pastebin
picture = ./kant-logo.svg
alt = the Kant pastebin logo
```

Lines are `key = value`; a line without an `=` is a comment.  A value stays on
one line and must not begin with a space.

| key | what it is |
|---|---|
| `origin` | the URL every code, link and card starts with; it carries no `#` of its own |
| `caption` | the line of text printed on the share card |
| `picture` | the small picture placed in the middle of the code (a path, a URL, or a `data:` URI) |
| `alt` | the picture's text description |

* `parseConfig_renderConfig` — what the client writes is read back exactly.
* `parseConfig_ignores_comment` — a line without an `=` changes nothing.

The page reads `kant.config` next to `index.html` and falls back to the
built-in default when there is none (a `file://` copy, an offline visit).  The
static publisher reads the same file:

```
node scripts/sneakernet.mjs publish site                     # origin from kant.config
node scripts/sneakernet.mjs publish site --base https://x/    # or override it
node scripts/sneakernet.mjs publish site --config other.config
```

## 2. The whole URL, in every code

```
addressUrl cfg addr = cfg.origin ++ "#" ++ addr
pasteUrl   cfg p    = addressUrl cfg p.witness
qrPayload  cfg e    = addressUrl cfg (encode e)
```

* `pasteUrl_length` — the URL is the origin, a `#`, and exactly 64 hex characters.
* `pasteUrl_address`, `urlAddress_addressUrl` — the address comes back out of the URL.
* `qrPayload_origin_prefix` — the code starts with the configured site, so a
  scanner that knows nothing about this program still offers an openable link…
* `parseQrPayload_qrPayload` — …while the client recovers the exact payload
  from the fragment.
* `pasteUrl_fits_qr` — with any plausible origin the URL fits in one QR code.

The chat invitation and the sneakernet mailbag now travel the same way: the
code shown in sections 7 and 8 of the page is the *link*, not the bare payload.

## 3. The share card: the URL, a line of text, a picture

A **card** is four strings: the URL, the caption printed with the code, the
picture drawn in the middle of the code, and that picture's description.
`cardSvg` renders them as one SVG document:

```
<!--kzcard:6b7a63617264:…              <- the card itself, machine readable
-->
<svg …>
  <title>kant-zk-pastebin</title>
  <a href="https://kant.cicada71.net/#ff81…"> … the modules … </a>
  <image href="./kant-logo.svg" …/>     <- the picture, in the middle
  <text …>kant-zk-pastebin</text>       <- the caption
  <text …>https://kant.cicada71.net/#ff81…</text>
</svg>
```

* `readCard_cardSvg` — the exported picture still carries the card it was made
  from, caption and logo included.
* `cardSvg_caption_visible`, `cardSvg_picture_used`, `cardSvg_url_visible` — the
  text, the picture and the whole URL really appear in the document.
* `card_text_no_markup` — whatever the user types, nothing can break out of its
  element; the caption is eRDFa-escaped and recovers exactly
  (`cardSvg_caption_recoverable`).
* `logo_area_bound` — the picture is a fifth of the code across, so it covers at
  most a twenty-fifth of the modules: well inside the error-correction budget.
* `cardOf_roundTrip` — end to end, the card of a post carries that post's page URL.

In the page, section 9 builds a card from the current paste (or any URL you
type), lets you set the text and drop in a picture, and then: **Show**, **Copy
the URL**, **Copy the card**, **Download SVG**, **Download PNG**, **Share…**
(the system share sheet) and **Send it to the room**.  It also reads a card
back — from a pasted card, a pasted link, or a dropped `.svg`.

## 4. Sharing it in chat

Two ways, both proved:

* **Into a room.** The card is the body of an ordinary self-certifying chat
  message: `readChatCard_chatMsg` says it arrives as the same card, and
  `chatMsg_tamper` says a line whose witness disagrees with its body is refused
  rather than displayed as somebody else's card.  The chat view renders a card
  as its picture, its text and its link.
* **Into any other chat**, as plain text — `chatText`:

  ```
  kant-zk-pastebin
  https://kant.cicada71.net/#ff81…f605
  6b7a63617264:68747470733a2f2f…
  ```

  A human reads the first two lines; `readChatText_chatText` says the third
  line brings the card back whole, whatever the human text above it says.

## Scope

The Lean layer is the specification and is proved.  `web/kant-site.mjs`,
`web/index.html` and `scripts/sneakernet.mjs` are unverified transcriptions
pinned to the Lean-computed vectors in `web/site-test.mjs`.  A card's text is
not secret: it travels in the clear, exactly like the link it carries.
