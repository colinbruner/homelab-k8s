#!/usr/bin/env bash
# Shared connect logic for bootstrap.sh and verify.sh (sourced, not executed).
# Requires env: REPO_TYPE, KOPIA_PASSWORD, KOPIA_OVERRIDE_USERNAME,
# KOPIA_OVERRIDE_HOSTNAME, KOPIA_CACHE_SIZE_MB, plus backend vars
# (GCS_BUCKET + GCS_CREDENTIALS_FILE, or S3_BUCKET + S3_ENDPOINT + AWS creds).

repo_args() {
  case "$REPO_TYPE" in
    gcs)
      backend_args=(gcs --bucket="$GCS_BUCKET" --credentials-file="$GCS_CREDENTIALS_FILE")
      ;;
    s3)
      backend_args=(s3 --bucket="$S3_BUCKET" --endpoint="$S3_ENDPOINT"
        --access-key="$AWS_ACCESS_KEY_ID" --secret-access-key="$AWS_SECRET_ACCESS_KEY")
      if [[ -n "${S3_REGION:-}" ]]; then
        backend_args+=(--region="$S3_REGION")
      fi
      ;;
    *)
      echo "[ERROR] unsupported REPO_TYPE: ${REPO_TYPE}" >&2
      return 1
      ;;
  esac
  common_args=(
    --override-username="$KOPIA_OVERRIDE_USERNAME"
    --override-hostname="$KOPIA_OVERRIDE_HOSTNAME"
    --cache-directory=/app/cache
    --content-cache-size-mb="$KOPIA_CACHE_SIZE_MB"
    --metadata-cache-size-mb="$KOPIA_CACHE_SIZE_MB"
    --enable-actions
  )
}

repo_connect() {
  repo_args
  kopia repository connect "${backend_args[@]}" "${common_args[@]}"
}

repo_connect_or_create() {
  repo_args
  kopia repository connect "${backend_args[@]}" "${common_args[@]}" \
    || kopia repository create "${backend_args[@]}" "${common_args[@]}"
}
