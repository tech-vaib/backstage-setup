#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if command -v yq >/dev/null 2>&1; then
  echo "Validating YAML syntax..."
  find catalog -type f \( -name "*.yaml" -o -name "*.yml" \) -print0 |
    while IFS= read -r -d '' file; do
      yq e '.' "$file" >/dev/null
      echo "OK: $file"
    done
else
  echo "yq is not installed; skipping YAML syntax validation."
  echo "Install yq if you want local YAML syntax validation."
fi

echo "Catalog validation completed."
