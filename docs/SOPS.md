# Secrets with sops

Three scripts. `init` once, `set` to store, `run` to consume.

```bash
scripts/sops-init.sh                              # once
scripts/sops-set.sh CLOUDFLARE_API_TOKEN          # prompts, value hidden
scripts/sops-run.sh npx wrangler deploy           # runs with secrets loaded
```

## Why two recipients

Every encrypted file carries **two** recipients, and each solves a different
problem:

| | Used by | Needs |
|---|---|---|
| **age** | systemd, CI, scripts — anything unattended | nothing; no tty, no passphrase |
| **pgp** `7704975004FFD465FBCCA34E4C1B1A28AE5C7E4F` | you, by hand, from any machine | your GPG key only |

The split exists because your GPG key is passphrase-protected, so gpg needs a
pinentry and cannot decrypt from a service:

```
gpg: public key decryption failed: Inappropriate ioctl for device
```

Age has no such problem. So **age is what actually runs things** — it is the
recipient systemd and CI use, and it works headlessly right now. The GPG key is
your personal escape hatch: it means you can read a secret on a laptop that has
never seen this box, with no age file present. If the age key is ever lost, the
files are still readable by you.

Verify both are present in any file:

```bash
grep -E "recipient: age1|fp: " .sops/registry.sops.yaml
```

## The three scripts

### `sops-init.sh` — check keys, write config

Idempotent; safe to re-run. It never overwrites key material, and only rewrites
`.sops.yaml` when the recipients actually change (backing up the old one).

It reports honestly rather than assuming success. Right now it says:

```
warn  passphrase NOT cached; unattended PGP decrypt will fail.
      That is fine: services use the age recipient.
```

That warning is the expected state, not a problem to fix.

### `sops-set.sh` — store a secret

```bash
scripts/sops-set.sh NAME 'value'      # value in argv (visible in ps)
scripts/sops-set.sh NAME              # prompts with echo off — prefer this
scripts/sops-set.sh --list            # names only, never values
scripts/sops-set.sh --delete NAME
```

Secrets are top-level keys in one file, `.sops/registry.sops.yaml`. One file is
easier to reason about than many.

Every write is **read back and verified** before success is reported:

```
ok    NAME stored and verified (mode 600, …/.sops/registry.sops.yaml)
```

This is deliberate. `otc-desk-sops.service` reported success for days while
decrypting nothing, so a store that cannot prove it wrote something is treated
as a failure.

### `sops-run.sh` — consume secrets

```bash
scripts/sops-run.sh npx wrangler deploy
scripts/sops-run.sh --only CLOUDFLARE_API_TOKEN -- ./deploy.sh
scripts/sops-run.sh --list
scripts/sops-run.sh --allow-missing ./cmd     # opt out of failing
```

**It fails loudly.** If decryption fails it prints why and exits non-zero
*without running the command*:

```
sops-run: decrypt failed:
  Failed to get the data key required to decrypt the SOPS file.
sops-run: cannot read …/.sops/registry.sops.yaml
```

This is the opposite of `tracker/scripts/with-secrets.sh`, which degrades to
ambient-only on failure. That is right for a wrapper you put around everything
and wrong for a tool you are about to trust with a deploy. Use
`--allow-missing` when you genuinely need no secrets.

**Ambient environment wins** over registry values, so an override, CI, or an
outer `sops-run` always takes priority. Safely nestable.

Secrets reach the child as real environment variables and never touch disk in
plaintext.

## Using it from a service

The `aristotle-secrets` pattern is the good one — decrypt as root into tmpfs,
hand consumers an `EnvironmentFile`, never put a secret on a command line:

```nix
export SOPS_AGE_KEY_FILE=/home/mdupont/.config/sops/age/keys.txt;
${pkgs.sops}/bin/sops -d /path/.sops/registry.sops.yaml \
  | grep '^CLOUDFLARE_API_TOKEN=' > /run/app.env
chmod 0600 /run/app.env
```

Then the consumer just does `EnvironmentFile=/run/app.env`. `/run` is tmpfs, so
it is never on disk. Set `after = [ "your-secrets.service" ]`.

## Two traps, both hit while building this

Both are sops 3.8.1 behaviours (`/usr/local/bin/sops`). Nixpkgs ships 3.12.2
at `/nix/store/na9cdkq3wpq0pqwh3d86l1bzm7hsnygm-sops-3.12.2/bin/sops`, and
systemd units get that one via `${pkgs.sops}` — so **`$PATH` and a service can
be different sops versions**. The generated config works on both.

**1. Recipients must be scalars, not YAML lists.**

```yaml
pgp:                       # 3.12.2: fine
  - KEY1
  - KEY2
pgp: "KEY1,KEY2"           # 3.8.1 and 3.12.2: both fine
```

3.8.1 dies with `cannot unmarshal !!seq into string` *before doing any work*.
The comment in the old repo `.sops.yaml` blamed this for breaking "every sops
call made from the repository root" — real, but it was never the thing actually
blocking the deploy.

**2. A config whose rules do not match the file aborts everything.**

```
error loading config: no matching creation rules found
```

This fires **even when `--age`/`--pgp` are passed explicitly** — 3.8.1 still
demands a matching rule. It is why encrypting through a `mktemp` file outside
`.sops/` fails. The generated config therefore uses one catch-all rule:

```yaml
creation_rules:
  - path_regex: .*
```

`.*` cannot fail this way. It looks lazy; it is the only form that works when
the tool encrypts via a temp file.

## Not done, and worth knowing

- **The Cloudflare API token is still not stored.** Nothing here supplies it;
  the scripts only manage what you give them. A populated token exists in
  `tracker/secrets/credentials.enc.json` under `cloudflare.api_token` — whether
  it has Workers Scripts write scope is unverified.
- `SOPS_CONFIG` still points at the placeholder
  `~/projects/system-manager/.sops.yaml`, which has no `creation_rules` key.
  Any unit using it will not decrypt. Not touched in this pass.
- Access is **mdupont only**. `mdupont2` and `agent` cannot decrypt — their age
  key file is `0600 mdupont`.
- `sops-run.sh` exports only scalar values; nested JSON objects are skipped.
- Rotation is not handled. Re-run `sops-set.sh` with a new value to rotate, but
  nothing revokes the old ciphertext.