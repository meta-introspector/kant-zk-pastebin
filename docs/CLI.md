# The command line: two agents, one link, and curl

Everything the browser client does can be done from a terminal, by a person
or by an agent, over exactly the requests the browser makes. This page is the
proof and the recipe.

* the client: `scripts/kant-cli.mjs`
* the shell demonstration: `scripts/two-agents.sh`
* the specification, proved: `RequestProject/Kant/Cli.lean`
* the checks: `node web/cli-test.mjs` (77) and `node web/cli-page-test.mjs` (10)

## The situation

The page is static. Two agents therefore need some channel they already
share — Telegram, Discord, a tweet, an SMS, a pastebin — over which they can
send each other **one line of text**. That line is a link:

```
http://your.site/#kzinvite:<relay>:<secret>:<who>
```

The part before the `#` is the site, and it is all a static host is ever asked
for (`Kant.Cli.link_page_static`). Everything the sender adds — the relay to
meet on, and the secret whose digest is the room — is in the fragment, which a
browser never puts on the wire. Whoever opens that URL lands in the same room
(`Kant.Cli.join_same_room`), and so does anybody who pastes it into the client
wrapped in the sentence they typed around it
(`Kant.Cli.messy_join_same_room`).

## Two agents, from a terminal

```sh
node server/relay.mjs --port 8787 --static web        # somewhere both can reach

# agent A
node scripts/kant-cli.mjs --state a.json --name agent-a open --relay http://127.0.0.1:8787
node scripts/kant-cli.mjs --state a.json link          # send this line in any chat
node scripts/kant-cli.mjs --state a.json say 'hello from the first terminal'

# agent B, having been sent that line
node scripts/kant-cli.mjs --state b.json --name agent-b join 'hey, come in here: <link> .'
node scripts/kant-cli.mjs --state b.json read
node scripts/kant-cli.mjs --state b.json say 'hello back'

# agent A again
node scripts/kant-cli.mjs --state a.json read
```

`--json` makes every command print a machine-readable object instead, which is
what an agent should use: `open` gives `{room, link, page, invite}`, `read`
gives `{view: [{sender, seq, text}], cursor, curl}`, and so on.

## The same thing in curl

The client never does anything a terminal cannot. Ask it for the command
instead of the result:

```sh
$ node scripts/kant-cli.mjs --state a.json curl say 'typed into the shell'
curl -sS -X POST -H content-type:text/plain --data-binary 6b7a63686174:…:… http://127.0.0.1:8787/room/<room>

$ node scripts/kant-cli.mjs --state b.json curl read
curl -sS http://127.0.0.1:8787/room/<room>?cursor=0
```

Run either line and the room moves. `--transport curl` makes the client itself
shell out to the `curl` binary for every request, and `--print-curl` prints
each command as it is run.

Two facts make this trustworthy rather than merely plausible:

* **the printed command is the request** — `Kant.Cli.parseCurlLine_curlLine`
  says the line, read back, is exactly the request the client meant to make,
  and `say_curl_roundTrip` / `pollFrom_curl_roundTrip` discharge its side
  conditions for the requests a session actually makes (no space occurs in a
  room, a cursor or a chat line: they are hex, colons and digits);
* **the relay answers the URL the way the browser is answered** —
  `Kant.Cli.say_eq_browserSay` and `Kant.Cli.poll_eq_browserPoll` say that
  going over `/room/<room>` and `?cursor=<n>` leaves the client and the relay
  in exactly the state the in-memory browser client leaves them in.

One shell note: a query string contains a `?`, which some shells treat as a
glob. `set -f` before pasting a poll command, or quote the URL.

## The whole demonstration in one script

```sh
PORT=8787 sh scripts/two-agents.sh
```

It starts a relay, opens a room as agent A, prints the chat message A would
send, joins as agent B from that pasted message, posts with a curl command
typed out in full, reads it back with another, and finally checks that the two
agents display the same conversation. It exits non-zero if they do not.

## Adding information to the URL

An invitation is not the only thing a link can carry. `bag` puts the whole
conversation in one URL, and `load` takes it back out — with no relay in the
picture at all:

```sh
node scripts/kant-cli.mjs --state a.json bag        # http://your.site/#kzbag:…
node scripts/kant-cli.mjs --state c.json load 'http://your.site/#kzbag:…'
```

`Kant.Cli.loadUrl` is the rule for what a URL turns out to carry;
`loadUrl_link` and `loadUrl_bagUrl` say each kind loads as what it is, and a
mailbag link provably names no room (`findInvite_bagUrl`), so the two can
never be confused.

## The same results as in the browser

`node web/cli-page-test.mjs` runs `web/index.html` itself, in a minimal DOM,
pointed at the link a terminal agent printed — as if it had been pasted into a
browser's address bar out of a chat window. The page loads the URL, walks into
the room, shows the terminal's line, answers, and the terminal hears the
answer; the two sides are then compared line for line.

`node web/cli-test.mjs` additionally runs the browser client
(`web/kant-net.mjs`, the module the page uses) against the same relay and the
same link and checks that its transcript is the CLI's transcript.

## The commands

| command | what it does |
|---|---|
| `open --relay <url>` | open a fresh room |
| `link` | the link to send in a chat |
| `invite` | the bare `kzinvite:` code |
| `room` | the room this client is in |
| `whoami` | name, relay, room, counters |
| `join <text>` | join the room named by a pasted message |
| `load <url>` | load a URL: a room to join, or a conversation to take in |
| `say <text>` | say something |
| `read` | read the room and print the conversation |
| `bag` | the conversation as one link, no relay needed |
| `watch [--wait 25]` | keep reading |
| `health` | is the relay there? |
| `curl read \| say <text> \| health` | print the command instead of running it |

Options: `--state <file>`, `--json`, `--transport fetch|curl`, `--print-curl`,
`--origin <url>`, `--config <file>`, `--name <id>`, `--relay <url>`.

## What is proved

`RequestProject/Kant/Cli.lean`, no `sorry`, standard axioms only:

| theorem | in words |
|---|---|
| `parseCurlLine_curlLine` | the printed command is the request |
| `say_curl_roundTrip`, `pollFrom_curl_roundTrip` | every step of a session is one curl command |
| `route_roomPath`, `route_pollPath` | the relay's router reads the URLs the client builds |
| `say_eq_browserSay`, `poll_eq_browserPoll` | the CLI over HTTP = the browser client |
| `link_page_static` | a static host is asked for the page and nothing else |
| `link_carries_invite` | the added information comes back out of the fragment |
| `join_same_room`, `join_same_relay`, `messy_join_same_room` | loading the link puts you in the sender's room |
| `loadUrl_link`, `loadUrl_bagUrl`, `findInvite_bagUrl` | each kind of URL loads as what it is |
| `meet_fresh`, `cliSession_agree` | two agents, one link: both hold both messages and display the same conversation |
| `parseArgv_printArgv` | every command reads back as itself |
| `digitsValue_decNum` | a cursor written out is the cursor read back |
