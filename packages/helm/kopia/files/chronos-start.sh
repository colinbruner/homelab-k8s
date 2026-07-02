#!/usr/bin/env bash
# Chronos "start" ping (before-snapshot-root action). Resolves the per-source
# token via sources.map. Best-effort: never blocks or fails the backup.
: "${CHRONOS_PING_BASE:=https://chronos.bruner.family/ping}"
name=$(awk -F'|' -v p="${KOPIA_SOURCE_PATH:-}" '$1 == p {print $2}' /app/actions/sources.map 2> /dev/null)
if [ -n "$name" ] && [ -f "/app/chronos/${name}" ]; then
  token=$(cat "/app/chronos/${name}")
  curl -fsS -m 10 "${CHRONOS_PING_BASE}/${token}/start?rid=${KOPIA_SNAPSHOT_ID:-}" > /dev/null 2>&1
fi
exit 0
