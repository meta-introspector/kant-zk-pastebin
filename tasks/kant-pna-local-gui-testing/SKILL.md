---
name: kant-pna-local-gui-testing
description: Chrome PrivateNetworkAccess blocks local GUI tests of the kant paste page — public Pages origin cannot fetch the LAN-pinned relay. Workaround: mint test passes against the CF relay twin. Use when GUI-testing paste.html locally, debugging Failed to fetch on post, or interpreting LocalNetworkAccessPermissionDenied.
---

# kant-pna-local-gui-testing

See SYSTEM.md. Local GUI tests of paste.html must use the CF relay twin
(kant-zk-relay.jmikedupont2.workers.dev); the LAN-pinned
solana.solfunmeme.com is unreachable from a public Pages origin in
Chrome >=142 (PNA). Chrome 153 ignores the old disable-features flags.
