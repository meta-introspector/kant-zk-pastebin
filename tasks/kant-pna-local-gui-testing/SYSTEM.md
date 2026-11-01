# Task: kant-pna-local-gui-testing

- **Name:** kant-pna-local-gui-testing
- **Priority:** P2
- **Area:** kant-zk, browser, testing
- **Status:** Documented — workaround in place
- **Tags:** kant-zk, browser, testing, test

## Problem
Chrome >=142 PrivateNetworkAccess blocks fetches from a public Pages origin
(kant-zk-pastebin.pages.dev) to a private IP. On introspector.local,
`/etc/hosts` pins `solana.solfunmeme.com -> 192.168.68.62`, so any local
GUI test of paste.html against the local relay fails with
`net::ERR_BLOCKED_BY_LOCAL_NETWORK_ACCESS_CHECKS` /
`LocalNetworkAccessPermissionDenied`. The old
`--disable-features=BlockInsecurePrivateNetworkRequests,...` flags no
longer help in Chrome 153.

## Impact
Paste page "doesn't work" locally — post silently fails with "Failed to
fetch". This is why the page appeared broken in early GUI tests.

## Workaround (current)
Mint test passes against the CF relay twin
`https://kant-zk-relay.jmikedupont2.workers.dev` — fully public, no PNA.
External users never hit this (real DNS -> public IP).

## Proper fix candidates
- paste.html `effectiveRelay`: prefer CF twin when the page origin is
  Pages and the invite relay is private (needs explicit config or a
  probe with clear error text).
- Surface the PNA error in the page log instead of bare "Failed to fetch".

## Evidence
- CDP capture 2026-09-29: `Network.loadingFailed` with
  `corsError: LocalNetworkAccessPermissionDenied`
- docs/GUI2LEAN4-PROOF.md in pastebin-lean

## SPARQL Context

```
Blocks mentioning 'kant-pna-local-gui-testing' in descriptions: 4
  01551220  n0x-pi/.dotagents/tasks/kant-pna-local-gui-testing/SYSTEM.md  [1444 bytes]
  01551220  n0x-pi/.dotagents/tasks/kant-pna-local-gui-testing/SKILL.md  [669 bytes]
  01551220  dotagents/tasks/kant-pna-local-gui-testing/SKILL.md  [669 bytes]
  01551220  dotagents/tasks/kant-pna-local-gui-testing/SYSTEM.md  [1444 bytes]

```
