#!/bin/bash
# Script combines collection of latest versions of operators and images used in values.yaml (values-tools.yaml) and
# outputs newest frozen values

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tmpdir=$(mktemp -d)
trap "rm -rf $tmpdir" EXIT

# Run both scripts in parallel
"${SCRIPT_DIR}/get-images-versions.sh" > "$tmpdir/tags.yaml" &
PID_IMAGES="$!"
"${SCRIPT_DIR}/get-operator-versions.sh" > "$tmpdir/operators.yaml" &
PID_OPERATORS="$!"

wait "$PID_IMAGES" || { echo "ERROR: Images versions script failed" && exit 1; }
wait "$PID_OPERATORS" || { echo "ERROR: Operator versions script failed" && exit 1; }

# Merge and output YAML
yq eval-all '. as $item ireduce ({}; . * $item)' "$tmpdir/tags.yaml" "$tmpdir/operators.yaml"
