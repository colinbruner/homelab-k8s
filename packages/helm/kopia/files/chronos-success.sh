#!/usr/bin/env bash
# Chronos "success" ping (after-snapshot-root action; runs only on success).
# Resolves the per-source token via sources.map. Best-effort: never fails the backup.
: "${CHRONOS_PING_BASE:=https://chronos.bruner.family/ping}"
name=$(awk -F'|' -v p="${KOPIA_SOURCE_PATH:-}" '$1 == p {print $2}' /app/actions/sources.map 2> /dev/null)
if [ -n "$name" ] && [ -f "/app/chronos/${name}" ]; then
  token=$(cat "/app/chronos/${name}")
  curl -fsS -m 10 "${CHRONOS_PING_BASE}/${token}?rid=${KOPIA_SNAPSHOT_ID:-}" > /dev/null 2>&1
fi
exit 0
