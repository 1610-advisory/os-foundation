#!/usr/bin/env bash
# Start the local Forgejo stack. Safe to run again.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/../lib/common.sh"

usage() {
  cat << 'EOF'
usage: up.sh

Start Forgejo, the Actions runner, and the Docker sidecar.
Safe to run again. Does not delete data.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi
if [ $# -ne 0 ]; then
  usage >&2
  exit 1
fi

osf_need_cmd docker curl
if ! docker info >/dev/null 2>&1; then
  echo "FAIL: Docker is not running" >&2
  exit 1
fi

root=$(osf_acme_root)
osf_acme_compose up -d

if ! osf_wait_http "$(osf_acme_url)/api/healthz" 60; then
  if ! osf_wait_http "$(osf_acme_url)/api/v1/version" 15; then
    echo "FAIL: Forgejo did not become ready" >&2
    exit 1
  fi
fi

i=0
until docker exec osf-acme-dind docker info >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -gt 40 ]; then
    echo "FAIL: DinD did not become ready" >&2
    exit 1
  fi
  sleep 2
done

i=0
until docker exec osf-acme-dind test -f /certs/client/cert.pem; do
  i=$((i + 1))
  if [ "$i" -gt 30 ]; then
    echo "FAIL: DinD certificates were not created" >&2
    exit 1
  fi
  sleep 1
done
docker exec -u 0 osf-acme-dind chmod -R a+rX /certs/client

docker build -t osf-acme-job:local -f "$root/tests/acme/forgejo/job.Dockerfile" "$root/tests/acme/forgejo"
docker save osf-acme-job:local | docker exec -i osf-acme-dind docker load

echo "forgejo OK"
echo "dind OK"
echo "job-image OK"
