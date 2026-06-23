#!/usr/bin/env bash
# Chronos "start" ping (before-snapshot-root action).
# Best-effort: never blocks or fails the backup.
: "${CHRONOS_PING_BASE:=https://chronos.bruner.family/ping}"
[ -n "$CHRONOS_TOKEN" ] && \
  curl -fsS -m 10 "${CHRONOS_PING_BASE}/${CHRONOS_TOKEN}/start?rid=${KOPIA_SNAPSHOT_ID}" >/dev/null 2>&1
exit 0
