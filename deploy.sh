#!/usr/bin/env bash
set -euo pipefail

PASTEBIN_DIR="${PASTEBIN_DIR:-/home/mdupont/pastebin}"
DOMAIN="${PASTEBIN_DOMAIN:-solana.solfunmeme.com}"
BIND_PORT="${PASTEBIN_BIND_PORT:-8090}"
BETA_PORT="${PASTEBIN_BETA_PORT:-8081}"
PUBLIC_URL="${PASTEBIN_PUBLIC_URL:-https://${DOMAIN}/pastebin/}"
FLAKE="${PASTEBIN_FLAKE:-${PASTEBIN_DIR}#systemConfigs.kant-pastebin-only}"
LOG_DIR="${PASTEBIN_DIR}/logs"

cd "$PASTEBIN_DIR"
mkdir -p "$LOG_DIR"

run_sudo() {
  if [ "${EUID}" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

systemctl_value() {
  local unit="$1"
  local prop="$2"
  local value
  value="$(systemctl show "$unit" -p "$prop" --value 2>/dev/null || true)"
  printf '%s' "${value:--}"
}

exec_binary() {
  local unit="$1"
  local exec_start
  exec_start="$(systemctl_value "$unit" ExecStart)"
  if [[ "$exec_start" =~ path=([^[:space:];]+) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "unknown"
  fi
}

port_process() {
  local port="$1"
  local listener
  listener="$(ss -H -tlnp "sport = :$port" 2>/dev/null | head -n1 || true)"
  if [[ -z "$listener" ]]; then
    printf '%s' "-"
  elif [[ "$listener" =~ users:\(\(\"([^\"]+)\" ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "unknown"
  fi
}

nginx_conf_path() {
  local exec_start
  exec_start="$(systemctl_value nginx.service ExecStart)"
  if [[ "$exec_start" =~ -c[[:space:]]+([^[:space:]]+) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' ""
  fi
}

http_code() {
  local url="$1"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 "$url" 2>/dev/null || true)"
  printf '%s' "${code:-000}"
}

diagnose() {
  echo ""
  echo "Kant Pastebin diagnostic report"
  echo "  Timestamp: $(date -Iseconds)"
  echo ""

  echo "-- service status --"
  for svc in ssl-selfsigned.service kant-pastebin.service nginx.service nora.service test-result-tile.service dasl-tile-server.service; do
    status="$(systemctl is-active "$svc" 2>/dev/null || true)"
    status="${status:-not-found}"
    enabled="$(systemctl is-enabled "$svc" 2>/dev/null || true)"
    enabled="${enabled:-n/a}"
    pid="$(systemctl_value "$svc" MainPID)"
    since="$(systemctl_value "$svc" ActiveEnterTimestamp)"
    printf '  %-30s status=%-12s enabled=%-12s pid=%-8s since=%s\n' "$svc" "$status" "$enabled" "$pid" "$since"
  done
  echo ""

  echo "-- port bindings --"
  for port in "$BIND_PORT" "$BETA_PORT" 4000 18090; do
    proc="$(port_process "$port")"
    if [ "$proc" != "-" ]; then
      echo "  :$port LISTENING pid=$proc"
    else
      echo "  :$port NOTHING LISTENING"
    fi
  done
  echo ""

  echo "-- nginx proxy mapping --"
  local conf
  conf="$(nginx_conf_path)"
  if [ -n "$conf" ] && [ -f "$conf" ]; then
    pastebin_backend="$(grep -A8 "location.* /pastebin/" "$conf" 2>/dev/null | grep proxy_pass | head -n1 | sed 's/.*proxy_pass[[:space:]]*//;s/;$//' || true)"
    beta_backend="$(grep -A8 "location.* /pastebin/beta/" "$conf" 2>/dev/null | grep proxy_pass | head -n1 | sed 's/.*proxy_pass[[:space:]]*//;s/;$//' || true)"
    echo "  /pastebin/      -> ${pastebin_backend:-not configured}"
    echo "  /pastebin/beta/ -> ${beta_backend:-not configured}"
  else
    echo "  /pastebin/      -> nginx config not found"
    echo "  /pastebin/beta/ -> nginx config not found"
  fi
  echo "  nginx status: $(systemctl is-active nginx.service 2>/dev/null || true)"
  echo ""

  echo "-- HTTP health checks --"
  for port in "$BIND_PORT" "$BETA_PORT" 4000 18090; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 "http://127.0.0.1:${port}/" 2>/dev/null || true)"
    code="${code:-000}"
    health="$(curl -s --connect-timeout 2 "http://127.0.0.1:${port}/health" 2>/dev/null || true)"
    health="${health:-no response}"
    printf '  :%-5s HTTP=%s /health=%s\n' "$port" "$code" "$health"
  done
  echo "  ${PUBLIC_URL} HTTP=$(http_code "$PUBLIC_URL")"
  echo ""

  echo "-- last deploy info --"
  unit_file="/etc/systemd/system/kant-pastebin.service"
  if [ -f "$unit_file" ] || [ -L "$unit_file" ]; then
    echo "  Unit file: $unit_file"
    echo "  ExecStart: $(systemctl_value kant-pastebin.service ExecStart)"
    echo "  BIND_ADDR: $(systemctl show kant-pastebin.service --value --property=Environment 2>/dev/null | tr ' ' '\n' | grep '^BIND_ADDR=' || true)"
    echo "  Modified:  $(stat -c '%y' "$unit_file" 2>/dev/null | cut -d. -f1)"
  else
    echo "  Unit file NOT FOUND at $unit_file"
  fi

  binary="$(exec_binary kant-pastebin.service)"
  if [ "$binary" != "unknown" ] && [ -x "$binary" ]; then
    echo "  Binary: $binary"
    echo "  Built:  $(stat -c '%y' "$binary" 2>/dev/null | cut -d. -f1)"
  else
    echo "  Binary: $binary"
  fi
  echo ""

  echo "-- recent journal logs --"
  journalctl -u kant-pastebin.service --no-pager -n 30 > "$LOG_DIR/kant-pastebin.log" 2>&1 || printf '  (no journal entries)\n'
  echo ""

  echo "-- system-manager result --"
  if [ -L "${PASTEBIN_DIR}/result" ]; then
    sm_result="$(readlink -f "${PASTEBIN_DIR}/result")"
    echo "  Result symlink: ${PASTEBIN_DIR}/result -> ${sm_result}"
    echo "  Built: $(stat -c '%y' "${PASTEBIN_DIR}/result" 2>/dev/null | cut -d. -f1)"
  else
    echo "  No result symlink found"
  fi
  echo ""

  echo "-- data paths --"
  for p in /mnt/data1/kant/pastebin /mnt/data1/spool/uucp/pastebin /mnt/data1/nora; do
    if [ -d "$p" ]; then
      size="$(du -sh "$p" 2>/dev/null | cut -f1 | tr -d '\n' || true)"
      echo "  $p (${size:-?})"
    else
      echo "  $p MISSING"
    fi
  done
  echo ""

  echo "-- summary --"
  main_active="$(systemctl is-active kant-pastebin.service 2>/dev/null || true)"
  main_active="${main_active:-not-found}"
  port_ok="$(port_process "$BIND_PORT")"
  if [ "$main_active" = "active" ] && [ "$port_ok" != "-" ]; then
    echo "  Service is UP and port ${BIND_PORT} is listening"
  elif [ "$main_active" = "active" ]; then
    echo "  Service is active but port ${BIND_PORT} is NOT listening"
  else
    echo "  Service is DOWN or not loaded"
    echo "    Quick fix: sudo systemctl restart kant-pastebin.service"
    echo "    Full fix:  bash ${PASTEBIN_DIR}/deploy.sh deploy"
  fi
  echo ""
}

follow_logs() {
  echo "Following kant-pastebin.service journal (Ctrl+C to stop)"
  journalctl -u kant-pastebin.service -f --no-pager | tee "$LOG_DIR/kant-pastebin.log"
}

repair_direct_symlinks() {
  local store_path="$1"
  local services_json="${store_path}/services/services.json"
  [ -f "$services_json" ] || return 0

  local units
  units="$(jq -r 'keys[] | select(test("\\.(service|timer)$"))' "$services_json")"
  while IFS= read -r unit; do
    [ -n "$unit" ] || continue
    local target
    target="$(jq -r --arg unit "$unit" '.[$unit].storePath // empty' "$services_json")"
    if [ -n "$target" ]; then
      run_sudo ln -sfn "$target" "/etc/systemd/system/$unit"
    fi
  done <<< "$units"
  run_sudo systemctl daemon-reload
}

deploy() {
  echo "Building system-manager configuration: $FLAKE"
  STORE_PATH="$(nix build "$FLAKE" --no-link --json | jq -r '.[0].outputs.out')"
  echo "Built: $STORE_PATH"

  if [ ! -x "$STORE_PATH/bin/activate" ]; then
    echo "ERROR: activation script not found or not executable at $STORE_PATH/bin/activate" >&2
    exit 1
  fi

  echo "Activating system-manager configuration"
  run_sudo "$STORE_PATH/bin/activate"
  run_sudo systemctl daemon-reload

  echo "Repairing direct systemd unit symlinks"
  repair_direct_symlinks "$STORE_PATH"

  echo "Restarting pastebin application service"
  run_sudo systemctl restart kant-pastebin.service

  echo ""
  echo "Post-deploy verification"
  diagnose
}

restart_pastebin() {
  echo "Restarting pastebin application service"
  run_sudo systemctl restart kant-pastebin.service
  diagnose
}

usage() {
  cat <<USAGE
Usage: $0 [deploy|restart|diagnose|logs|pipelight|full-deploy|status]

Commands:
  deploy        Build, activate, repair symlinks, restart services, then diagnose
  restart       Restart already-installed pastebin services, then diagnose
  diagnose      Print service, port, nginx, health, and log diagnostics
  logs          Follow kant-pastebin.service journal
  pipelight     Run: nix run .#pipelight -- run deploy
  full-deploy   Run: nix run .#pipelight -- run full-deploy
  status        Alias for diagnose
USAGE
}

case "${1:-diagnose}" in
  deploy)
    deploy
    ;;
  restart)
    restart_pastebin
    ;;
  diagnose|status)
    diagnose
    ;;
  logs)
    follow_logs
    ;;
  pipelight)
    cd "$PASTEBIN_DIR"
    nix run .#pipelight -- run deploy
    ;;
  full-deploy)
    cd "$PASTEBIN_DIR"
    nix run .#pipelight -- run full-deploy
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
