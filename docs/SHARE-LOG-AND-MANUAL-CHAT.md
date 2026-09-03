# Share the log, post it to the store, and run the whole thing with no server

Two additions, and one guarantee behind both: **nothing here contacts
anything.** Every code below is text a person moves — into a chat, a
message, a photograph of a screen — and the receiving side is a page that
reads text.

Proved in `RequestProject/Kant/ShareLog.lean` and
`RequestProject/Kant/Handoff.lean`; transcribed, unverified, in
`web/kant-sharelog.mjs`, and checked against the Lean vectors by
`node web/sharelog-test.mjs`.

## Share the log

The **Share the log** button (in the app, under *More → Diagnostics*, and
on `web/diag.html`) hands the run over in whichever of three shapes fits
the situation.

| shape | what it is | Lean |
|---|---|---|
| text | the readable run with the machine-readable block underneath; the system share sheet if this device has one, the clipboard otherwise | `logText`, `logText_roundTrip` |
| a post | the run put in the content-addressed store, so it has a witness, a page and a link like anything else the app holds | `logPaste`, `postLog` |
| chat messages | the run cut into numbered messages, each inside a tweet, collected on the other side in any order | `chatParts`, `readChatParts` |

What never goes out is a secret. The report is built by `shareReport`,
which withholds every event quoting anything held and replaces the room by
its eight-character handle:

* `shared_no_secret` — no held secret occurs in the sentence or the detail
  of any shared event;
* `shareReport_room_ne` — a room longer than eight characters is provably
  not its handle;
* `shared_keeps` — nothing *else* is withheld, so the run stays useful;
* `posted_no_secret`, `chat_no_secret` — the same holds for what the store
  holds and for what arrives through a chat.

## Post it to the store

`postLog` is `Store.put` on the run-as-a-post. The store is
content-addressed, so:

* `postLog_resolves` — after posting, the address answers;
* `postLog_idem` — posting the same run twice changes nothing;
* `postLog_monotone` — nothing already held is lost;
* `postLog_in_feed` — a posted run shows up in the feed like any post;
* `logPaste_witness_congr` — two people whose runs came out the same post
  the very same block, whatever they called it;
* `logPaste_content_roundTrip` — what the store holds parses back to
  exactly the run that was shared.

The store is this device's own: one bundle in `localStorage` under
`kant-store`, written with `Kant.Clipboard.copyAll` and read back with
`pasteAll`. Every page of the app uses that same key, so a run posted in
one page is a block the others hold. There is no upload, and nothing to
run.

## No server: the manual steps

`web/hand.html` is the whole system with the network removed. Two people,
any chat window, four steps:

1. you copy your code and send it in the chat;
2. they paste it into the same page on their device;
3. they copy their code and send it back;
4. you paste theirs.

That is `Kant.Handoff.script`, and carrying it out is `Kant.Handoff.run`.

* `script_serverless` — and, more strongly, `serverless_all`: a move is
  either *copy this out* or *paste this in*, and neither can ask for a
  server, so no script the app can show you needs one;
* `run_delivers`, `run_delivers_back`, `run_keeps` — each direction
  delivers, and nothing already held is lost;
* `run_agree` — after the four steps both sides display exactly the same
  conversation;
* `run_after_write_new` — say something new, run the steps again, and what
  you said is on the other screen;
* `codes_script_isAscii` — everything sent is plain ASCII, so a chat, an
  SMS, an alt text or a photograph of a QR code carries it unchanged;
* a code too long for one message goes as a numbered thread
  (`Kant.Uucp.thread_fits_tweet`), collected in any order
  (`readThread_perm`).

The rule that comes with the mode is `Kant.Uucp.Node.mem_sneakernet_iff`:
**you are exactly as up to date as the last code you pasted.** An edited
or incomplete code is refused whole and changes nothing
(`bag_rejects_forgery`, `paste_bad`).

### Handing a block over the same way

The last card of `hand.html` takes a block, a bundle of blocks, or
somebody's shared run, and puts it in this device's store:

* `carry_resolves` — a post copied into a chat and pasted on the other side
  lands under exactly the address it left with;
* `carry_agrees` — two stores that both answer an address answer with the
  same block: agreement by content, not by trust;
* `carry_idem`, `carry_monotone` — taking the same block twice changes
  nothing, and nothing already held is lost;
* `logScript_delivers` — the run itself survives the trip, in as many
  messages as it takes.

## Trying it

```
python3 -m http.server -d web 8080     # any static host will do; nothing runs
# open http://localhost:8080/hand.html in two different browsers, or on two
# devices with no network in common, and move the codes by hand
node web/sharelog-test.mjs   # 64 checks of the sharing, posting and carrying rules
node web/handpage-test.mjs   # 32 checks driving hand.html itself; asserts zero fetches
```

`web/handpage-test.mjs` installs a `fetch` that throws and counts, and
checks at the end that it was never called: the page provably made no
request to anything.
