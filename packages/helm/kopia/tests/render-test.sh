#!/usr/bin/env bash
# Render tests for the kopia chart: helm-template each fixture, run
# grep-based assertions, then validate with kubeconform when available.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0

assert_contains() { # file substring description
  if ! grep -qF -- "$2" "$1"; then
    echo "FAIL: $3 (missing: $2)"
    fail=1
  fi
}

assert_not_contains() { # file substring description
  if grep -qF -- "$2" "$1"; then
    echo "FAIL: $3 (forbidden: $2)"
    fail=1
  fi
}

assert_count() { # file regex expected description
  local n
  n=$(grep -cE -- "$2" "$1" || true)
  if [[ "$n" -ne "$3" ]]; then
    echo "FAIL: $4 (expected $3 matches of '$2', got $n)"
    fail=1
  fi
}

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

helm template backup . --namespace backup \
  -f tests/fixtures/single-gcs.yaml > "$out/single.yaml"
helm template backup . --namespace backup \
  -f tests/fixtures/multi-backend.yaml > "$out/multi.yaml"

if helm template backup . --namespace backup \
    -f tests/fixtures/bad-repo-ref.yaml > /dev/null 2>&1; then
  echo "FAIL: expected render failure for unknown repository reference"
  fail=1
fi

# ---- assertions ----
# Task 3: per-source PVs/PVCs + per-repo config PVCs
assert_contains "$out/single.yaml" "name: backup-src-documents" "namespaced source PV name (avoids legacy backup-documents PV collision)"
assert_contains "$out/single.yaml" "path: /var/nfs/shared/Documents" "source PV nfs path"
assert_contains "$out/single.yaml" "volumeName: backup-src-documents" "source PVC pinned to its PV"
assert_contains "$out/single.yaml" "name: config-primary" "per-repository config PVC"
assert_contains "$out/single.yaml" "storageClassName: nfs-csi" "config PVC uses dynamic nfs-csi"
assert_count "$out/multi.yaml" "^kind: PersistentVolume$" 3 "one PV per source"
assert_count "$out/multi.yaml" "^kind: PersistentVolumeClaim$" 5 "3 source PVCs + 2 config PVCs"
# Task 4: scripts configmap + sources.conf
assert_contains "$out/single.yaml" "name: backup-primary-scripts" "per-repo scripts configmap"
assert_contains "$out/single.yaml" "/Volumes/Documents|15 4 * * *|3|0|14|8|12|2|true" "documents sources.conf line (explicit retention)"
assert_contains "$out/single.yaml" "repo_connect_or_create" "bootstrap uses connect-first"
assert_contains "$out/single.yaml" "kopia maintenance set" "maintenance ownership pinned"
assert_contains "$out/multi.yaml" "/data/media|0 5 * * 0|2|0|0|4|6|0|false" "media sources.conf line (omitted retention -> 0)"
assert_count "$out/multi.yaml" "^  sources.conf: " 2 "one sources.conf per repository"
assert_count "$out/multi.yaml" "/data/media\|0 5" 1 "media source appears only in its own repository's conf"
# Task 5: chronos actions + sources.map
assert_contains "$out/single.yaml" "name: backup-actions" "shared actions configmap"
assert_contains "$out/single.yaml" "/Volumes/Documents|documents" "sources.map entry"
assert_contains "$out/single.yaml" "/app/chronos/" "token resolved from mounted secret dir"
# Task 6: per-repository server certificate
assert_contains "$out/single.yaml" "kind: Certificate" "cert-manager certificate rendered"
assert_contains "$out/single.yaml" "secretName: backup-primary-tls" "tls secret name consumed by deployment"
assert_contains "$out/single.yaml" "backup-primary.backup.svc.cluster.local" "service FQDN SAN"
assert_count "$out/multi.yaml" "^kind: Certificate$" 2 "one certificate per repository"
# Task 7: hardened server deployment + service
assert_count "$out/single.yaml" "^kind: Deployment$" 1 "single repo -> single deployment"
assert_count "$out/multi.yaml" "^kind: Deployment$" 2 "one server deployment per repository"
assert_count "$out/multi.yaml" "^kind: Service$" 2 "one service per repository"
assert_not_contains "$out/single.yaml" "allow-extremely-dangerous-unauthenticated-server-on-the-network" "dangerous flag removed"
assert_not_contains "$out/single.yaml" "--insecure" "insecure flag removed"
assert_not_contains "$out/single.yaml" "--without-password" "without-password flag removed"
assert_not_contains "$out/single.yaml" "envFrom" "no wholesale secret env dump"
assert_contains "$out/single.yaml" "--tls-cert-file=/tls/tls.crt" "server TLS enabled"
assert_contains "$out/single.yaml" "containerPort: 51515" "kopia default HTTPS port"
assert_contains "$out/single.yaml" "runAsNonRoot: true" "non-root pod"
assert_contains "$out/single.yaml" "readOnlyRootFilesystem: true" "read-only root fs"
assert_contains "$out/single.yaml" "KOPIA_SERVER_CONTROL_PASSWORD" "control API password from secret"
assert_contains "$out/single.yaml" "tcpSocket" "tcp probes (kopia basic-auth 401 breaks httpGet)"
assert_contains "$out/single.yaml" 'value: "root"' "legacy identity override preserved"
assert_contains "$out/single.yaml" "mountPath: /Volumes/Documents" "legacy source mount path preserved"
assert_count "$out/multi.yaml" "mountPath: /data/media$" 1 "media source mounted only on its own repo server"
assert_contains "$out/multi.yaml" "name: AWS_SECRET_ACCESS_KEY" "s3 credentials via env secretKeyRef"
# Task 8: verify cronjob
assert_contains "$out/single.yaml" "name: backup-primary-verify" "verify cronjob per repository"
assert_contains "$out/single.yaml" "schedule: \"30 6 1 * *\"" "monthly off-peak schedule"
assert_contains "$out/single.yaml" "key: verify-primary" "per-repo verify chronos token key"
assert_contains "$out/single.yaml" 'value: "verify"' "distinct verify identity (not maintenance owner)"
assert_count "$out/multi.yaml" "^kind: CronJob$" 2 "one verify job per repository"
# ---- end assertions ----

if command -v kubeconform > /dev/null 2>&1; then
  for f in "$out/single.yaml" "$out/multi.yaml"; do
    kubeconform -strict -ignore-missing-schemas \
      -schema-location default \
      -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
      < "$f"
  done
fi

if [[ "$fail" -ne 0 ]]; then
  echo "render tests FAILED"
  exit 1
fi
echo "render tests OK"
