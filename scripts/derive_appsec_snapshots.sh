#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_DIR="${SCRIPT_DIR}/../integration_tests/snapshots/logs"
BASE_RUNTIME="${1:-3.3}"
RUNTIMES=("3.2" "3.3" "3.4" "4.0")

token() { echo "ruby${1//./}"; }

base_token="$(token "$BASE_RUNTIME")"
base_file="${LOGS_DIR}/appsec-request_${base_token}.log"

if [ ! -f "$base_file" ]; then
  echo "base snapshot not found: $base_file" >&2
  exit 1
fi

for rt in "${RUNTIMES[@]}"; do
  [ "$rt" = "$BASE_RUNTIME" ] && continue
  target_token="$(token "$rt")"
  sed -e "s/${base_token}/${target_token}/g" -e "s/${BASE_RUNTIME//./\\.}\.X/${rt}.X/g" \
    "$base_file" > "${LOGS_DIR}/appsec-request_${target_token}.log"
  echo "derived appsec-request_${target_token}.log from ${base_token}"
done
