#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: scripts/swift-safe.sh <command...>" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "${script_dir}/.." && pwd)"

log_file="$(mktemp)"
cleanup() {
  rm -f "$log_file"
}
trap cleanup EXIT

run_command() {
  set +e
  (cd "$root_dir" && "$@") 2>&1 | tee "$log_file"
  local status="${PIPESTATUS[0]}"
  set -e
  return "$status"
}

has_stale_module_cache_error() {
  grep -q "PCH was compiled with module cache path" "$log_file" \
    || grep -q "missing required module 'SwiftShims'" "$log_file"
}

clean_swift_state() {
  echo "Detected stale Swift module cache. Cleaning local build state and retrying once..."
  (
    cd "$root_dir"
    swift package clean || true
    swift package reset || true
    rm -rf .build
  )
}

if run_command "$@"; then
  exit 0
fi

if has_stale_module_cache_error; then
  clean_swift_state
  run_command "$@"
  exit $?
fi

exit 1
