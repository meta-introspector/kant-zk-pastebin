#!/usr/bin/env bash
# sops-set.sh — store or update a secret in the sops registry.
#
#   scripts/sops-set.sh CLOUDFLARE_API_TOKEN 'the-token-value'
#   scripts/sops-set.sh CLOUDFLARE_API_TOKEN            # prompt, value hidden
#   scripts/sops-set.sh --delete OPS_CONTROL_TOKEN
#   scripts/sops-set.sh --list
#
# Secrets live as top-level keys in ONE registry file, .sops/registry.sops.yaml,
# so there is a single thing to encrypt, back up and reason about. This is the
# shape sops-run.sh expects.
#
# The value never reaches argv (visible in `ps`) or history: it is read from a
# pipe, and the encrypted file is written with mode 600.
set -euo pipefail

REPO="${SOPS_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REGISTRY="$REPO/.sops/registry.sops.yaml"

die()  { printf '  ERROR %s\n' "$*" >&2; exit 1; }
ok()   { printf '  ok    %s\n' "$*"; }
say()  { printf '%s\n' "$*"; }

export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

# ── modes ───────────────────────────────────────────────────────────────────
case "${1:-}" in
  --list|-l)
    if [ ! -f "$REGISTRY" ]; then say "no registry yet at $REGISTRY"; exit 0; fi
    say "secrets in $REGISTRY:"
    sops -d "$REGISTRY" 2>/dev/null | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\):.*/  \1/p'
    exit 0 ;;
  --delete)
    shift
    [ $# -eq 1 ] || die "usage: sops-set.sh --delete NAME"
    [ -f "$REGISTRY" ] || die "no registry at $REGISTRY"
    DEL="$(mktemp)"; trap 'rm -f "$DEL"' EXIT
    # Decrypt to JSON so the edit below is a real parse, not a regex over
    # whatever YAML shape sops happened to emit.
    sops -d --output-type json "$REGISTRY" > "$DEL" 2>/dev/null || die "decrypt failed"
    python3 - "$1" "$DEL" <<'PY' || die "no such secret '$1'"
import json, sys
name, path = sys.argv[1], sys.argv[2]
doc = json.load(open(path))
if name not in doc:
    sys.exit(1)
del doc[name]
json.dump(doc, open(path, 'w'), indent=2, sort_keys=True)
PY
    chmod 600 "$DEL"
    AGE_PUB="$(grep -o 'age1[a-z0-9]*' "$SOPS_AGE_KEY_FILE" | head -1)"
    PGP_FPR="$(grep -oE 'pgp: *"[^"]+"' "$REPO/.sops.yaml" | head -1 | sed 's/.*"\(.*\)"/\1/')"
    sops --encrypt --age "$AGE_PUB" --pgp "$PGP_FPR" \
      --input-type json --output-type yaml "$DEL" > "$REGISTRY.tmp" \
      || { rm -f "$REGISTRY.tmp"; die "re-encrypt failed"; }
    mv "$REGISTRY.tmp" "$REGISTRY"
    chmod 600 "$REGISTRY"
    if sops -d --output-type json "$REGISTRY" 2>/dev/null | grep -q "\"$1\""; then
      die "$1 still present after delete — refusing to claim success"
    fi
    ok "deleted $1 (verified absent)"
    exit 0 ;;
  --help|-h|"")
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
esac

NAME="${1:-}"; VALUE="${2:-}"
[ -n "$NAME" ] || die "usage: sops-set.sh NAME [VALUE] | --delete NAME | --list"
[[ "$NAME" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "'$NAME' is not a valid key name (letters, digits, underscore)"

# No value given → prompt without echo.
if [ -z "$VALUE" ] && [ ! -t 0 ]; then
  die "no value given and stdin is not a terminal; pass the value as an argument"
fi
if [ -z "$VALUE" ]; then
  read -r -s -p "value for $NAME: " VALUE; echo
fi

command -v sops >/dev/null 2>&1 || die "sops not found"

# ── merge into the registry ─────────────────────────────────────────────────
mkdir -p "$REPO/.sops"
WORK="$(mktemp)"; trap 'rm -f "$WORK"' EXIT

if [ -f "$REGISTRY" ]; then
  # --output-type json: the registry is written as YAML (readable in review),
  # but this merge step needs a shape python can parse reliably.
  sops -d --output-type json "$REGISTRY" > "$WORK" 2>/dev/null \
    || die "cannot decrypt $REGISTRY — run scripts/sops-init.sh and check your age key"
else
  printf '{}\n' > "$WORK"
fi

# Recipients are read from .sops.yaml and passed explicitly rather than relied
# on via creation_rules. sops matches creation_rules against the path of the
# file it is handed, and the working copy here is a mktemp file in /tmp, which
# matches no rule. Naming the recipients also makes the destination
# independent of where sops happens to be run from — which, on a box with a
# stale SOPS_CONFIG pointing at a placeholder, is not a safe thing to assume.
AGE_PUB="$(grep -o 'age1[a-z0-9]*' "$SOPS_AGE_KEY_FILE" | head -1)"
PGP_FPR="$(grep -oE 'pgp: *"[^"]+"' "$REPO/.sops.yaml" | head -1 | sed 's/.*"\(.*\)"/\1/')"
[ -n "$AGE_PUB" ] || die "no age public key in $SOPS_AGE_KEY_FILE"
[ -n "$PGP_FPR" ] || die "no pgp fingerprint in $REPO/.sops.yaml — run scripts/sops-init.sh"
RECIPIENTS=(--age "$AGE_PUB" --pgp "$PGP_FPR")

python3 - "$NAME" "$VALUE" "$WORK" <<'PY'
import json, sys
name, value, path = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    doc = json.load(open(path))
except Exception:
    # Registry may be YAML-ish from a hand edit; rebuild from scratch rather
    # than silently dropping unknown content.
    doc = {}
doc[name] = value
json.dump(doc, open(path, 'w'), indent=2, sort_keys=True)
PY

chmod 600 "$WORK"
sops --encrypt "${RECIPIENTS[@]}" --input-type json --output-type yaml "$WORK" > "$REGISTRY.tmp" 2>/tmp/.sops-err.$$ \
  || { cat /tmp/.sops-err.$$ >&2; rm -f "$REGISTRY.tmp"; die "encryption failed"; }

mv "$REGISTRY.tmp" "$REGISTRY"
chmod 600 "$REGISTRY"

# Prove it reads back before claiming success. A store that cannot be read is
# not a store, and this box has already been bitten by a config that looked fine
# and decrypted to nothing.
if sops -d --output-type json "$REGISTRY" 2>/dev/null \
     | python3 -c 'import json,sys; sys.exit(0 if sys.argv[1] in json.load(sys.stdin) else 1)' "$NAME"; then
  ok "$NAME stored and verified (mode 600, $REGISTRY)"
else
  die "$NAME was written but did not read back — refusing to claim success"
fi