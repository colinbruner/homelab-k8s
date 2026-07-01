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
