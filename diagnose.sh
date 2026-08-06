#!/usr/bin/env bash
set -uo pipefail

PASTEBIN_DIR="${PASTEBIN_DIR:-/mnt/data1/kant/pastebin}"
DOMAIN="${PASTEBIN_DOMAIN:-solana.solfunmeme.com}"
BIND_PORT="${PASTEBIN_BIND_PORT:-8090}"
BETA_PORT="${PASTEBIN_BETA_PORT:-8081}"
PUBLIC_URL="${PASTEBIN_PUBLIC_URL:-https://${DOMAIN}/pastebin/}"
LOG_DIR="${PASTEBIN_DIR}/logs"

mkdir -p "$LOG_DIR"

failed=0

section() {
  printf '\n-- %s --\n' "$1"
}

svc_prop() {
  local unit="$1"
  local prop="$2"
  systemctl show "$unit" -p "$prop" --value 2>/dev/null || printf '%s' "-"
}

http_code() {
  local url="$1"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 "$url" 2>/dev/null || true)"
  printf '%s' "${code:-000}"
}

port_process() {
  local port="$1"
  local listener
  listener="$(ss -H -tlnp "sport = :$port" 2>/dev/null | head -n1 || true)"
  if [ -z "$listener" ]; then
    printf '%s' "-"
  elif [[ "$listener" =~ users:\(\(\"([^\"]+)\" ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "unknown"
  fi
}

nginx_conf_path() {
  local exec_start
  exec_start="$(svc_prop nginx.service ExecStart)"
  if [[ "$exec_start" =~ -c[[:space:]]+([^[:space:];]+) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  elif [ -f /etc/nginx/nginx.conf ]; then
    printf '%s' /etc/nginx/nginx.conf
  fi
}

nginx_conf_files() {
  local conf
  conf="$(nginx_conf_path)"
  if [ -n "$conf" ] && [ -f "$conf" ]; then
    printf '%s\n' "$conf"
  fi

  if [ -d /etc/nginx/conf.d ]; then
    for f in /etc/nginx/conf.d/*.conf; do
      [ -f "$f" ] && printf '%s\n' "$f"
    done
  fi

  if [ -d /etc/nginx/sites-enabled ]; then
    for f in /etc/nginx/sites-enabled/*; do
      [ -f "$f" ] && printf '%s\n' "$f"
    done
  fi
}

proxy_target() {
  local pattern="$1"
  local conf target
  for conf in $(nginx_conf_files); do
    target="$(grep -A12 "$pattern" "$conf" 2>/dev/null | grep -m1 'proxy_pass' | sed 's/.*proxy_pass[[:space:]]*//;s/;$//' || true)"
    if [ -n "$target" ]; then
      printf '%s' "$target"
      return 0
    fi
  done
  printf 'not configured'
}

print_service() {
  local unit="$1"
  local status enabled pid since substate
  status="$(systemctl is-active "$unit" 2>/dev/null || true)"
  status="${status:-not-found}"
  enabled="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
  enabled="${enabled:-n/a}"
  pid="$(svc_prop "$unit" MainPID)"
  since="$(svc_prop "$unit" ActiveEnterTimestamp)"
  substate="$(svc_prop "$unit" SubState)"
  printf '  %-30s active=%-12s substate=%-12s enabled=%-12s pid=%-8s since=%s\n' "$unit" "$status" "$substate" "$enabled" "$pid" "$since"
  # Don't flag oneshot services (Type=oneshot) as failed when inactive — they're supposed to exit
  # Also don't flag services not found (unit file may not be in current config)
  local unit_type
  unit_type="$(svc_prop "$unit" Type)"
  if [ "$status" != "active" ] && [ "$unit_type" != "oneshot" ] && [ -n "$unit_type" ]; then
    failed=1
  fi
}

section "services"
for svc in kant-pastebin.service nginx.service nora.service; do
  print_service "$svc"
done
# ssl-selfsigned is a oneshot — check separately, don't fail if inactive
print_service "ssl-selfsigned.service"

section "failed units"
# Only flag failed units that are part of kant-pastebin-only config
# (ignore stale timers/services from all-services config)
failed_units="$(systemctl --failed --no-legend 2>/dev/null || true)"
if [ -n "$failed_units" ]; then
  # Match only exact service names from kant-pastebin-only config
  pastebin_failed="$(echo "$failed_units" | grep -E 'kant-pastebin\.service|nora\.service|nora-dir\.service|svg2anim-worker\.service|nginx\.service|nginx-log-setup\.service|ssl-selfsigned\.service' || true)"
  other_failed="$(echo "$failed_units" | grep -vE 'kant-pastebin\.service|nora\.service|nora-dir\.service|svg2anim-worker\.service|nginx\.service|nginx-log-setup\.service|ssl-selfsigned\.service' || true)"
  if [ -n "$other_failed" ]; then
    echo "  (non-pastebin, informational):"
    echo "$other_failed" | sed 's/^/    /'
  fi
  if [ -n "$pastebin_failed" ]; then
    printf '%s\n' "$pastebin_failed"
    failed=1
  else
    echo "  none (pastebin-relevant)"
  fi
else
  echo "  none"
fi

section "ports"
# Only check pastebin-relevant ports (8090, 8081, 4000)
for port in "$BIND_PORT" "$BETA_PORT" 4000; do
  proc="$(port_process "$port")"
  if [ "$proc" = "-" ]; then
    echo "  :$port NOT LISTENING"
    if [ "$port" = "$BIND_PORT" ]; then
      failed=1
    fi
  else
    echo "  :$port LISTENING pid=$proc"
  fi
done

section "nginx proxy"
nginx_conf="$(nginx_conf_path)"
if [ -n "$nginx_conf" ] && [ -f "$nginx_conf" ]; then
  echo "  config: $nginx_conf"
  # Try multiple grep patterns: nix store config uses different formatting
  pastebin_target="$(proxy_target 'location[[:space:]]\+/pastebin/' || true)"
  if [ -z "$pastebin_target" ] || [ "$pastebin_target" = "not configured" ]; then
    pastebin_target="$(proxy_target '/pastebin' || true)"
  fi
  echo "  /pastebin/      -> ${pastebin_target:-not configured}"
  echo "  /pastebin/beta/ -> $(proxy_target 'location[[:space:]]\+/pastebin/beta/' || true)"
else
  echo "  config: not found"
  failed=1
fi
echo "  nginx active: $(systemctl is-active nginx.service 2>/dev/null || true)"
# Verify nginx is actually proxying to pastebin via HTTP check (more reliable than grep)
if [ "$(http_code "$PUBLIC_URL")" = "200" ]; then
  echo "  nginx → pastebin: OK (200)"
else
  echo "  nginx → pastebin: FAIL ($(http_code "$PUBLIC_URL"))"
fi

section "HTTP"
for url in "http://127.0.0.1:${BIND_PORT}/" "http://127.0.0.1:${BIND_PORT}/health" "http://127.0.0.1:${BETA_PORT}/" "http://127.0.0.1:4000/health" "$PUBLIC_URL"; do
  code="$(http_code "$url")"
  if [ "$code" = "000" ]; then
    echo "  ERROR $code $url"
    failed=1
  else
    echo "  $code $url"
  fi
done

section "unit and binary"
unit_file="/etc/systemd/system/kant-pastebin.service"
if [ -e "$unit_file" ] || [ -L "$unit_file" ]; then
  echo "  unit: $unit_file"
  echo "  modified: $(stat -c '%y' "$unit_file" 2>/dev/null | cut -d. -f1)"
else
  echo "  unit: missing $unit_file"
  failed=1
fi

exec_start="$(svc_prop kant-pastebin.service ExecStart)"
if [[ "$exec_start" =~ path=([^[:space:];]+) ]]; then
  binary="${BASH_REMATCH[1]}"
else
  binary="${exec_start%% *}"
fi
if [ -n "$binary" ] && [ -x "$binary" ]; then
  echo "  binary: $binary"
  echo "  binary modified: $(stat -c '%y' "$binary" 2>/dev/null | cut -d. -f1)"
else
  echo "  binary: not executable or not found ($binary)"
  failed=1
fi

env_line="$(svc_prop kant-pastebin.service Environment)"
for key in BIND_ADDR BASE_PATH BASE_URL UUCP_SPOOL RUST_LOG TILES_DIR; do
  value="$(printf '%s\n' "$env_line" | tr ' ' '\n' | grep "^${key}=" || true)"
  echo "  ${value:-$key=<unset>}"
done

section "recent errors"
journalctl -u kant-pastebin.service -p warning..alert --no-pager -n 50 > "$LOG_DIR/kant-pastebin-errors.log" 2>&1 || true
journalctl -u nginx.service -p warning..alert --no-pager -n 50 > "$LOG_DIR/nginx-errors.log" 2>&1 || true
journalctl -u nora.service -p warning..alert --no-pager -n 50 > "$LOG_DIR/nora-errors.log" 2>&1 || true

for log in "$LOG_DIR/kant-pastebin-errors.log" "$LOG_DIR/nginx-errors.log" "$LOG_DIR/nora-errors.log"; do
  if [ -s "$log" ]; then
    echo "  $log"
    tail -n 20 "$log" | sed 's/^/    /'
  else
    echo "  no recent errors in $(basename "$log")"
  fi
done

section "paths"
for p in "$PASTEBIN_DIR" /mnt/data1/spool/uucp/pastebin /mnt/data1/nora; do
  if [ -d "$p" ]; then
    size="$(du -sh "$p" 2>/dev/null | cut -f1)"
    echo "  $p (${size:-?})"
  else
    echo "  $p MISSING"
    failed=1
  fi
done

section "summary"
if [ "$failed" -eq 0 ]; then
  echo "  OK: deployment looks healthy"
  exit 0
fi

echo "  ERROR: deployment problems detected"
echo "  Review the failed units, missing ports, HTTP checks, and recent errors above."
exit 1
