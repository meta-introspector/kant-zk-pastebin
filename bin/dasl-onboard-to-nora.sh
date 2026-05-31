#!/usr/bin/env bash
# ─── DASL Submodule Onboarder to NORA ─────────────────────────────────────
# Iterates ~/dasl/.gitmodules, categorizes each submodule by type,
# and pushes its artifacts to the appropriate NORA registry endpoint.
#
# Registry mapping:
#   rust/*          → Cargo  (nora /cargo/…)
#   lang/go*        → Go     (nora /go/…)
#   lang/python*    → PyPI   (nora /pypi/…)
#   lang/js*        → npm    (nora /npm/…)
#   *               → Raw    (nora /raw/…)
#
# Usage:
#   ./dasl-onboard-to-nora.sh [--full]
#     --full  Re-upload even if the artifact already exists (default: skip)
#
# ENV:
#   NORA_URL     — Base URL (default: http://127.0.0.1:4000)
#   DASL_ROOT    — DASL repo root (default: ~/dasl)
# ============================================================================
set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────────
NORA_URL="${NORA_URL:-http://127.0.0.1:4000}"
DASL_ROOT="${DASL_ROOT:-${HOME}/dasl}"
FORCE="${1:-}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

# Log helper
log() { echo "[$(date +%H:%M:%S)] $*"; }
warn() { echo "[$(date +%H:%M:%S)] WARN: $*" >&2; }
err()  { echo "[$(date +%H:%M:%S)] ERROR: $*" >&2; exit 1; }

# ─── NORA connectivity check ────────────────────────────────────────────
check_nora() {
  if ! curl -sf "${NORA_URL}/health" >/dev/null 2>&1; then
    err "NORA not reachable at ${NORA_URL}. Is the service running?"
  fi
  log "NORA reachable at ${NORA_URL}"
}

# ─── Determine registry type from submodule path ────────────────────────
registry_type() {
  local path="$1"
  case "${path}" in
    rust/*)          echo "cargo" ;;
    lang/go*|external/*go*|lang/cid|lang/multicodec) echo "go" ;;
    lang/python*)    echo "pypi"  ;;
    lang/js*)        echo "npm"   ;;
    math/*)          echo "raw"   ;;
    external/*)      echo "raw"   ;;
    IMPL/*)          echo "raw"   ;;
    lang/*)          echo "raw"   ;;
    spec/*)          echo "raw"   ;;
    *)               echo "raw"   ;;
  esac
}

# ─── Push a raw artifact to NORA ─────────────────────────────────────────
push_raw() {
  local path="$1"  # submodule path
  [[ -d "${DASL_ROOT}/${path}" ]] || { warn "Submodule path does not exist: ${path}"; return 1; }

  local commit_name archive_name
  commit_name="$(cd "${DASL_ROOT}/${path}" && git rev-parse HEAD 2>/dev/null)" || return 1
  archive_name="dasl/${path}/${commit_name}.tar.gz"

  # Check if already uploaded (skip by default)
  local status
  status="$(curl -s -o /dev/null -w "%{http_code}" "${NORA_URL}/raw/${archive_name}")"
  if [[ "${status}" == "200" ]] && [[ "${FORCE}" != "--full" ]]; then
    log "  SKIP ${path} — already uploaded (${archive_name})"
    return 0
  fi

  # Build archive
  local tmp_archive="${WORK_DIR}/artifact.tar.gz"
  (cd "${DASL_ROOT}/${path}" && git archive --format=tar.gz \
    --prefix="$(basename "${path}")/" \
    -o "${tmp_archive}" HEAD 2>/dev/null) || {
    warn "  FAILED to create archive for ${path}"
    return 1
  }

  # Upload
  log "  UPLOAD ${path} → /raw/${archive_name} ($(stat -c%s "${tmp_archive}" 2>/dev/null || stat -f%z "${tmp_archive}" 2>/dev/null) bytes)"
  curl -sf -X PUT \
    --data-binary @"${tmp_archive}" \
    "${NORA_URL}/raw/${archive_name}" >/dev/null || {
    warn "  FAILED to upload ${path}"
    return 1
  }

  # Upload metadata
  local meta_file="${WORK_DIR}/meta.json"
  cat > "${meta_file}" <<METAEOF
{
  "submodule_path": "${path}",
  "commit": "$(cd "${DASL_ROOT}/${path}" && git rev-parse HEAD 2>/dev/null || echo "unknown")",
  "commit_msg": "$(cd "${DASL_ROOT}/${path}" && git log --format=%s -1 2>/dev/null || echo "unknown")",
  "commit_date": "$(cd "${DASL_ROOT}/${path}" && git log --format=%cI -1 2>/dev/null || echo "unknown")",
  "registry_type": "$(registry_type "${path}")",
  "remote_url": "$(cd "${DASL_ROOT}/${path}" && git config --get remote.origin.url 2>/dev/null || echo "unknown")",
  "uploaded_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
METAEOF
  curl -sf -X PUT \
    --data-binary @"${meta_file}" \
    "${NORA_URL}/raw/dasl/${path}/meta.json" >/dev/null || true

  # Create a "latest" symlink (no symlinks in raw, just copy latest archive)
  curl -sf -X PUT \
    --data-binary @"${tmp_archive}" \
    "${NORA_URL}/raw/dasl/${path}/latest.tar.gz" >/dev/null || true

  return 0
}

# ─── Push a submodule as a Cargo crate ───────────────────────────────────
push_cargo() {
  local path="$1"
  [[ -d "${DASL_ROOT}/${path}" ]] || { warn "Submodule path does not exist: ${path}"; return 1; }

  local cargo_toml="${DASL_ROOT}/${path}/Cargo.toml"
  [[ -f "${cargo_toml}" ]] || { warn "  No Cargo.toml for ${path} — falling back to raw"; push_raw "${path}"; return 1; }

  log "  CARGO ${path}"
  (
    cd "${DASL_ROOT}/${path}"

    # Build the crate
    cargo build --release 2>/dev/null || {
      warn "  BUILD FAILED for ${path} — falling back to raw"
      push_raw "${path}"
      return 1
    }

    # Package
    cargo package --allow-dirty 2>/dev/null || {
      warn "  PACKAGE FAILED for ${path} — falling back to raw"
      push_raw "${path}"
      return 1
    }

    # Upload to nora cargo registry
    cargo publish --registry nora --allow-dirty 2>/dev/null || {
      warn "  PUBLISH FAILED for ${path} — falling back to raw"
      push_raw "${path}"
      return 1
    }
  )
  return 0
}

# ─── Push a submodule as a Go module ────────────────────────────────────
push_go() {
  local path="$1"
  [[ -d "${DASL_ROOT}/${path}" ]] || { warn "Submodule path does not exist: ${path}"; return 1; }

  local go_mod="${DASL_ROOT}/${path}/go.mod"
  [[ -f "${go_mod}" ]] || { warn "  No go.mod for ${path} — falling back to raw"; push_raw "${path}"; return 1; }

  log "  GO ${path}"
  (
    cd "${DASL_ROOT}/${path}"

    local module_name module_version
    module_name="$(head -1 "${go_mod}" | awk '{print $2}')"
    module_version="v0.0.0-$(date -u +%Y%m%d%H%M%S)-$(git rev-parse --short HEAD 2>/dev/null || echo "0000000")"

    # Create module zip
    local zip_file="${WORK_DIR}/module.zip"
    git archive --format=zip -o "${zip_file}" HEAD 2>/dev/null || return 1

    # Generate .info file
    local info_file="${WORK_DIR}/module.info"
    cat > "${info_file}" <<INFOEOF
{
  "Version": "${module_version}",
  "Name": "${module_name}",
  "Short": "${module_version}"
}
INFOEOF

    # Generate .mod file
    cp "${go_mod}" "${WORK_DIR}/module.mod"

    # Upload to nora go proxy
    local module_encoded
    module_encoded="$(echo "${module_name}" | sed 's|/|/!|g')"

    curl -sf -X PUT \
      --data-binary @"${info_file}" \
      "${NORA_URL}/go/${module_encoded}/@v/${module_version}.info" >/dev/null || {
      warn "  FAILED to upload .info for ${path} — falling back to raw"
      push_raw "${path}"; return 1
    }

    curl -sf -X PUT \
      --data-binary @"${WORK_DIR}/module.mod" \
      "${NORA_URL}/go/${module_encoded}/@v/${module_version}.mod" >/dev/null || true

    curl -sf -X PUT \
      --data-binary @"${zip_file}" \
      "${NORA_URL}/go/${module_encoded}/@v/${module_version}.zip" >/dev/null || {
      warn "  FAILED to upload .zip for ${path} — falling back to raw"
      push_raw "${path}"; return 1
    }

    log "  Uploaded Go module: ${module_name}@${module_version}"
  )
  return 0
}

# ─── Main ────────────────────────────────────────────────────────────────
main() {
  check_nora

  local gitsubmodules="${DASL_ROOT}/.gitmodules"
  [[ -f "${gitsubmodules}" ]] || err "Cannot find ${gitsubmodules}"

  log "Reading submodules from ${gitsubmodules}"

  # Parse .gitmodules into name/path/url triplets
  local -A sub_name sub_path sub_url
  local current=""
  local idx=0
  while IFS= read -r line; do
    if [[ "${line}" =~ ^\[submodule\ \"([^\"]+)\"\]$ ]]; then
      current="${BASH_REMATCH[1]}"
      sub_name["${idx}"]="${current}"
    elif [[ "${line}" =~ ^[[:space:]]*path[[:space:]]*=[[:space:]]*(.+)$ ]]; then
      sub_path["${idx}"]="${BASH_REMATCH[1]}"
    elif [[ "${line}" =~ ^[[:space:]]*url[[:space:]]*=[[:space:]]*(.+)$ ]]; then
      sub_url["${idx}"]="${BASH_REMATCH[1]}"
      ((idx++)) || true
      current=""
    fi
  done < "${gitsubmodules}"

  local total="${idx}"
  local cargo_count=0 go_count=0 raw_count=0 skip_count=0 err_count=0

  log "Found ${total} submodules (excluding IMPL/users/atproto/* for brevity)"
  log ""

  for ((i=0; i<total; i++)); do
    local name="${sub_name[${i}]:-}"
    local path="${sub_path[${i}]:-}"
    # local url="${sub_url[${i}]:-}"

    [[ -n "${name}" ]] || continue
    [[ -n "${path}" ]] || continue

    # Skip massive atproto submodules (thousands of entries)
    [[ "${path}" == IMPL/users/atproto/* ]] && { ((skip_count++)) || true; continue; }
    [[ "${path}" == IMPL/crate2nix/* ]] && { ((skip_count++)) || true; continue; }

    # Ensure submodule is checked out
    if [[ ! -d "${DASL_ROOT}/${path}" ]]; then
      warn "  Submodule not checked out: ${path} — trying git submodule update..."
      (cd "${DASL_ROOT}" && git submodule update --init --depth 1 "${path}" 2>/dev/null) || {
        warn "  Cannot checkout ${path} — skipping"
        ((skip_count++)) || true
        continue
      }
    fi

    local rtype
    rtype="$(registry_type "${path}")"
    log "[$((i+1))/${total}] ${rtype}: ${path}"

    case "${rtype}" in
      cargo)
        push_cargo "${path}" && ((cargo_count++)) || ((err_count++))
        ;;
      go)
        push_go "${path}" && ((go_count++)) || ((err_count++))
        ;;
      *)
        push_raw "${path}" && ((raw_count++)) || ((err_count++))
        ;;
    esac
  done

  # Summary
  log ""
  log "═══════════════════════════════════════════════════"
  log "Onboarding complete!"
  log "  Cargo:  ${cargo_count}"
  log "  Go:     ${go_count}"
  log "  Raw:    ${raw_count}"
  log "  Errors: ${err_count}"
  log "  Skipped: ${skip_count}"
  log "═══════════════════════════════════════════════════"

  # Trigger NORA reindex for all changed registries
  log "Triggering NORA reindex..."
  curl -sf -X POST "${NORA_URL}/raw/-/reindex" >/dev/null 2>&1 || true
}
main "$@"
