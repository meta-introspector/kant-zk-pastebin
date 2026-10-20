#!/usr/bin/env bash
# sops-run.sh — run a command with the registry secrets in its environment.
#
#   scripts/sops-run.sh npx wrangler deploy
#   scripts/sops-run.sh printenv CLOUDFLARE_API_TOKEN
#   scripts/sops-run.sh --only CLOUDFLARE_API_TOKEN,CLOUDFLARE_ACCOUNT_ID -- ./deploy.sh
#   scripts/sops-run.sh --list
#
# Modeled on tracker/scripts/with-secrets.sh, with one deliberate difference:
# that wrapper degrades to "ambient env only" on a decrypt failure, which is
# correct for a wrapper you wrap around everything and wrong for a tool you
# are about to trust with a deploy. This one fails loudly by default, because
# the failure mode on this box has been a green unit that decrypted nothing.
#
# Override with --allow-missing when running somewhere that genuinely does not
# need the secrets.
#
# Precedence: the ambient environment WINS over registry values, so an explicit
# override, CI, or an outer sops-run always takes priority. Safely nestable.
set -euo pipefail

REPO="${SOPS_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REGISTRY="$REPO/.sops/registry.sops.yaml"

die()  { printf 'sops-run: %s\n' "$*" >&2; exit 1; }
ALLOW_MISSING=0
ONLY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --list|-l)
      [ -f "$REGISTRY" ] || die "no registry at $REGISTRY"
      sops -d --output-type json "$REGISTRY" 2>/dev/null \
        | python3 -c 'import json,sys; [print(k) for k in sorted(json.load(sys.stdin))]'
      exit 0 ;;
    --only)      ONLY="${2:?--only needs a comma-separated list}"; shift 2 ;;
    --allow-missing) ALLOW_MISSING=1; shift ;;
    --)          shift; break ;;
    -h|--help)   sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)          die "unknown option $1" ;;
    *)           break ;;
  esac
done

[ $# -ge 1 ] || die "usage: sops-run.sh [--only A,B] [--allow-missing] CMD [ARGS...]"

if [ -z "${SOPS_AGE_KEY_FILE:-}" ] && [ -f "$HOME/.config/sops/age/keys.txt" ]; then
  export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
fi

if [ ! -f "$REGISTRY" ]; then
  if [ "$ALLOW_MISSING" = 1 ]; then
    printf 'sops-run: no registry at %s — running with ambient env only\n' "$REGISTRY" >&2
    exec "$@"
  fi
  die "no registry at $REGISTRY
     create one:  scripts/sops-init.sh && scripts/sops-set.sh NAME VALUE
     or pass --allow-missing if this command genuinely needs no secrets"
fi

# Decrypt once, into the environment, never onto disk in plaintext.
if ! DEC="$(sops -d --output-type json "$REGISTRY" 2>/tmp/.sops-run-err.$$)"; then
  if [ "$ALLOW_MISSING" = 1 ]; then
    printf 'sops-run: decrypt failed — running with ambient env only\n' >&2
    exec "$@"
  fi
  printf 'sops-run: decrypt failed:\n' >&2
  sed 's/^/  /' /tmp/.sops-run-err.$$ >&2
  die "cannot read $REGISTRY — check SOPS_AGE_KEY_FILE and run scripts/sops-init.sh"
fi
rm -f /tmp/.sops-run-err.$$

[ -n "$DEC" ] || die "registry decrypted to nothing — refusing to run with an empty environment"

# Feed the child as KEY=VALUE lines. Ambient wins: only set what is absent.
while IFS= read -r kv; do
  k="${kv%%=*}"; v="${kv#*=}"
  if [ -n "$ONLY" ]; then
    case ",$ONLY," in *",$k,"*) ;; *) continue ;; esac
  fi
  # Indirect expansion tests whether the variable is already set.
  if [ -z "${!k+x}" ]; then
    export "$k=$v"
  fi
done < <(printf '%s' "$DEC" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
for k, v in sorted(doc.items()):
    if isinstance(v, (str, int, float, bool)) and "\n" not in str(v):
        print(f"{k}={v}")
')

# Prove at least one secret arrived, unless the caller narrowed the set to
# something the ambient environment already supplies.
LOADED="$(env | grep -cE '^[A-Z_][A-Z0-9_]*=' || true)"
if [ "$ALLOW_MISSING" != 1 ] && [ -z "$ONLY" ] && [ "$LOADED" -le 1 ]; then
  die "registry decrypted but nothing was exported — refusing to run
     (this is the failure that let a green unit decrypt nothing for days)"
fi

exec "$@"