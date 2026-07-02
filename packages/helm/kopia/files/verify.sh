#!/usr/bin/env bash
# Periodic snapshot verification (CronJob): connect as a distinct identity
# (never the maintenance owner) and sample file content to catch corruption
# before a restore is ever needed. Pings Chronos on success when configured.
set -euo pipefail

# shellcheck source=files/repo-connect.sh
source /app/scripts/repo-connect.sh

mkdir -p /app/config /app/cache

repo_connect
kopia snapshot verify \
  --verify-files-percent="${VERIFY_FILES_PERCENT}" \
  --file-parallelism="${VERIFY_FILE_PARALLELISM}"

if [[ -n "${CHRONOS_TOKEN:-}" ]]; then
  curl -fsS -m 10 "${CHRONOS_PING_BASE}/${CHRONOS_TOKEN}" > /dev/null || true
fi
echo "[INFO] verification complete"
