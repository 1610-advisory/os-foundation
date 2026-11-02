#!/usr/bin/env bash
# Shared helpers for the Acme harness. Source this file. Do not run it.

osf_acme_lib_dir() {
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
}

osf_acme_root() {
  local lib
  lib=$(osf_acme_lib_dir)
  CDPATH='' cd -- "$lib/../../.." && pwd
}

osf_acme_url() {
  printf '%s\n' "${OSF_ACME_URL:-http://localhost:3300}"
}

osf_acme_cache() {
  printf '%s\n' "${OSF_ACME_CACHE:-${HOME}/.cache/os-foundation/forgejo}"
}

osf_acme_token_dir() {
  printf '%s\n' "$(osf_acme_cache)/tokens"
}

osf_acme_admin_token() {
  printf '%s\n' "$(osf_acme_cache)/admin-token"
}

osf_acme_compose() {
  local root
  root=$(osf_acme_root)
  docker compose -p osf-acme -f "$root/tests/acme/forgejo/compose.yml" "$@"
}

# Copy the Tier A verdict file into DinD. Does not restart the runner.
osf_place_review_fake() {
  local root verdicts
  root=$(osf_acme_root)
  verdicts="$root/tests/acme/forgejo/verdicts.txt"
  if [ ! -f "$verdicts" ]; then
    echo "FAIL: verdicts file missing" >&2
    return 1
  fi
  docker exec osf-acme-dind mkdir -p /opt/os-review-fake
  docker exec -i osf-acme-dind sh -c 'cat > /opt/os-review-fake/verdicts.txt && chmod 644 /opt/os-review-fake/verdicts.txt' < "$verdicts"
}

osf_die() {
  echo "FAIL: $*" >&2
  exit 1
}

osf_need_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      osf_die "missing command: $cmd"
    fi
  done
}

osf_wait_http() {
  local url="$1"
  local tries="${2:-60}"
  local i=0
  while [ "$i" -lt "$tries" ]; do
    if curl -fsS --max-time 3 "$url" >/dev/null 2>&1; then
      return 0
    fi
    i=$((i + 1))
    sleep 2
  done
  return 1
}

osf_seat_field() {
  local seat="$1"
  local field="$2"
  local lib line
  lib=$(osf_acme_lib_dir)
  line=$(grep -E "^${seat}\\|" "$lib/seats.txt" | head -n 1 || true)
  if [ -z "$line" ]; then
    return 1
  fi
  # fields: seat|engine|forgejo_user|git_name|git_email
  case "$field" in
    seat) printf '%s\n' "$line" | cut -d'|' -f1 ;;
    engine) printf '%s\n' "$line" | cut -d'|' -f2 ;;
    user) printf '%s\n' "$line" | cut -d'|' -f3 ;;
    name) printf '%s\n' "$line" | cut -d'|' -f4 ;;
    email) printf '%s\n' "$line" | cut -d'|' -f5 ;;
    *) return 1 ;;
  esac
}

osf_seat_names() {
  local lib
  lib=$(osf_acme_lib_dir)
  cut -d'|' -f1 "$lib/seats.txt"
}

osf_forgejo_users() {
  local lib
  lib=$(osf_acme_lib_dir)
  cut -d'|' -f3 "$lib/seats.txt"
}
