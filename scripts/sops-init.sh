#!/usr/bin/env bash
# sops-init.sh — check key material and write the .sops.yaml config.
#
# Idempotent. Safe to re-run: it never overwrites an age identity or a GPG key,
# and it only rewrites .sops.yaml when the recipients change.
#
# The product uses TWO recipients on purpose:
#
#   age  — the unattended path. `sops -d` works with no tty, no pinentry and no
#          passphrase, which is what systemd units and CI need. This is the
#          recipient that actually gets used by machines.
#   pgp  — your personal path. Lets you decrypt by hand from any machine using
#          your GPG key alone, with no age file present. This is what lets you
#          read a secret on a laptop that has never seen this box.
#
# Both are recorded in every encrypted file, so a file stays readable by you
# even if the age key is lost, and readable by services even if your GPG
# passphrase is unavailable.
set -euo pipefail

AGE_PUB_DEFAULT="$(grep -o 'age1[a-z0-9]*' "$HOME/.config/sops/age/keys.txt" 2>/dev/null | head -1 || true)"
PGP_DEFAULT="7704975004FFD465FBCCA34E4C1B1A28AE5C7E4F"

REPO="${SOPS_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG="$REPO/.sops.yaml"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  warn  %s\n' "$*" >&2; }
die()  { printf '  ERROR %s\n' "$*" >&2; exit 1; }

# ── 1. tools ────────────────────────────────────────────────────────────────
say "== tools =="
command -v sops >/dev/null 2>&1 || die "sops not found in PATH"
ok "sops $(sops --version 2>/dev/null | head -1 | awk '{print $2}')"
if command -v age >/dev/null 2>&1; then ok "age present"; else warn "age not found — the unattended path will not work"; fi

# sops 3.8.x cannot parse a YAML *sequence* under creation_rules; it wants a
# scalar. 3.9+ accepts both. We emit the scalar form so one config works on
# both, which is why the generated file below quotes these as strings.
SOPS_VER="$(sops --version 2>/dev/null | head -1 | awk '{print $2}')"
case "$SOPS_VER" in
  3.[0-8].*) warn "sops $SOPS_VER needs scalar recipients; writing the 3.8-compatible form" ;;
esac

# ── 2. age identity ─────────────────────────────────────────────────────────
say ""
say "== age recipient =="
AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
if [ ! -f "$AGE_KEY_FILE" ]; then
  die "no age identity at $AGE_KEY_FILE
     create one with:  age-keygen -o $AGE_KEY_FILE   (then sops-init.sh --adopt)"
fi
chmod 600 "$AGE_KEY_FILE"
ok "identity present at $AGE_KEY_FILE (mode 600)"

# If the file holds a comment line and an AGE-SECRET-KEY line, the public half
# is not stored; derive it instead of asking the user for it.
if grep -q 'AGE-SECRET-KEY' "$AGE_KEY_FILE" && ! grep -q 'public key' "$AGE_KEY_FILE"; then
  DERIVED="$(age-keygen -y "$AGE_KEY_FILE" 2>/dev/null || true)"
  [ -n "$DERIVED" ] && AGE_PUB="$DERIVED" || die "could not derive the age public key from $AGE_KEY_FILE"
else
  AGE_PUB="$(grep -o 'age1[a-z0-9]*' "$AGE_KEY_FILE" | head -1)"
fi
[ -n "$AGE_PUB" ] || die "no age public key (age1…) found in $AGE_KEY_FILE"
ok "public recipient ${AGE_PUB:0:20}…"

# ── 3. GPG recipient ────────────────────────────────────────────────────────
say ""
say "== pgp recipient =="
PGP="${SOPS_PGP_FPR:-$PGP_DEFAULT}"
if ! gpg --list-keys "$PGP" >/dev/null 2>&1; then
  die "public key $PGP is not in the keyring
     import it first, e.g.:  gpg --keyserver keyserver.ubuntu.com --recv-keys $PGP
     or override with:        SOPS_PGP_FPR=<other-fpr> $0"
fi
ok "public key present in keyring"
if gpg --list-secret-keys "$PGP" >/dev/null 2>&1; then
  ok "secret key present (you can decrypt this box by hand)"
  if printf 'probe' | gpg --encrypt -a -r "$PGP" -o /tmp/.sops-init-probe.$$ 2>/dev/null \
     && gpg --decrypt /tmp/.sops-init-probe.$$ >/dev/null 2>&1; then
    ok "gpg-agent has the passphrase cached — decrypts headlessly"
  else
    warn "passphrase NOT cached; unattended PGP decrypt will fail.
     That is fine: services use the age recipient. To unlock anyway, run
     this in a real terminal:  gpg --decrypt /tmp/.sops-init-probe.$$"
  fi
  rm -f /tmp/.sops-init-probe.$$
else
  warn "secret key NOT present — this box cannot decrypt by PGP, but services still work via age"
fi

# ── 4. write .sops.yaml ─────────────────────────────────────────────────────
say ""
say "== config =="
mkdir -p "$REPO/.sops"

# One rule covering everything under .sops/, so a new file is encrypted without
# editing this config. The scalar (quoted) recipient form is deliberate: it is
# the only form sops 3.8.x accepts, and 3.9+ still reads it.
# Why one catch-all rule rather than a path-specific one: sops 3.8.x aborts
# with "error loading config: no matching creation rules found" the moment it
# finds a config whose rules do not match the file it was handed — even when
# --age/--pgp are also passed explicitly on the command line. sops-set.sh
# encrypts through a mktemp file outside .sops/, so any path-specific regex
# fails there. .* matches everything and cannot fail this way.
NEW_CONFIG="$(cat <<EOF
---
# Generated by scripts/sops-init.sh — do not hand-edit the recipients.
#
# Why one catch-all rule: sops 3.8.x aborts with "no matching creation rules
# found" as soon as it finds a config whose rules do not match the file it was
# given, even when recipients are also passed on the command line. A tool that
# encrypts through a temp file outside this directory would break on any
# path-specific regex. .* cannot fail that way.
#
#   age  — unattended path, used by systemd and CI. No passphrase needed.
#   pgp  — your personal path, so you can decrypt anywhere with just your GPG key.
creation_rules:
  - path_regex: .*
    age: "$AGE_PUB"
    pgp: "$PGP"
EOF
)"

if [ -f "$CONFIG" ] && [ "$(cat "$CONFIG")" = "$NEW_CONFIG" ]; then
  ok "$CONFIG already correct — left alone"
else
  if [ -f "$CONFIG" ]; then
    cp -p "$CONFIG" "$CONFIG.bak-$(date -u +%Y%m%d_%H%M%S)"
    warn "existing $CONFIG backed up before rewrite"
  fi
  printf '%s\n' "$NEW_CONFIG" > "$CONFIG"
  chmod 600 "$CONFIG"
  ok "wrote $CONFIG (mode 600)"
fi

say ""
say "Recipients:"
say "  age  $AGE_PUB"
say "  pgp  $PGP"
say ""
say "Next:"
say "  scripts/sops-set.sh NAME VALUE      store a secret"
say "  scripts/sops-run.sh CMD [ARGS...]   run a command with secrets loaded"