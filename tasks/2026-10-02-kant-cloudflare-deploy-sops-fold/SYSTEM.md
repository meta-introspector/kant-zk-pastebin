# Task: kant Cloudflare deploy + sops token fold (PARKED)
- **Priority:** P2
- **Tags:** deploy, security

**Status:** PARKED — operator pivot deferred 2026-10-01

## Scope
1. Deploy sync worker to kant Cloudflare account.
2. Reduce account-17 logging volume.
3. Fold the kant CF API token into the sops registry
   (secrets/credentials.enc.json via bin/vaultctl.mjs / scripts/secrets-to-sops.mjs).
   Token file: /var/spool/uucp/pastebin/20261001_161328_write_kant_v1_purple_fire_b881_key_cloudflare.txt
   — NEVER print, copy, or commit its contents.

## Related issues
#169 (no CF credential stored for acc-mesh-0), #173 (scoped API tokens),
#171 (stale FLEET_UI dupes in registry), #134 (operator checklist).

## Constraints
GitHub Actions workflow_dispatch-only; A5 blocked by Actions quota (#216).
Deploy path authority: docs/DEPLOY.md §1-5.
