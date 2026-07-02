#!/usr/bin/env bash
# Idempotent repository bootstrap (initContainer): connect-or-create the
# repository, apply per-source policies from sources.conf, pin maintenance
# ownership to the server identity.
set -euo pipefail

# shellcheck source=files/repo-connect.sh
source /app/scripts/repo-connect.sh

mkdir -p /app/config /app/cache

repo_connect_or_create
kopia repository status

while IFS='|' read -r path schedule latest hourly daily weekly monthly annual chronos; do
  [[ -z "$path" ]] && continue
  echo "[INFO] applying policy for ${path}"
  policy_args=(
    --compression=zstd-better-compression
    --snapshot-time-crontab="$schedule"
    --keep-latest="$latest"
    --keep-hourly="$hourly"
    --keep-daily="$daily"
    --keep-weekly="$weekly"
    --keep-monthly="$monthly"
    --keep-annual="$annual"
  )
  if [[ "$chronos" == "true" ]]; then
    policy_args+=(
      --before-snapshot-root-action=/app/actions/chronos-start.sh
      --after-snapshot-root-action=/app/actions/chronos-success.sh
      --action-command-mode=optional
    )
  fi
  kopia policy set "$path" "${policy_args[@]}"
done < /app/scripts/sources.conf

echo "[INFO] pinning maintenance ownership to ${KOPIA_OVERRIDE_USERNAME}@${KOPIA_OVERRIDE_HOSTNAME}"
kopia maintenance set \
  --owner="${KOPIA_OVERRIDE_USERNAME}@${KOPIA_OVERRIDE_HOSTNAME}" \
  --enable-quick=true \
  --enable-full=true
