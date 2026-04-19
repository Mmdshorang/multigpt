#!/usr/bin/env bash
set -euo pipefail

mode="${1:-artifact}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "${script_dir}/.." && pwd)"

usage() {
  cat <<'USAGE'
Resolve build version values.

Usage:
  scripts/resolve-build-version.sh [artifact|semver|build-number]

Modes:
  artifact      Filename-safe identifier (default)
  semver        App version in X.Y.Z format
  build-number  Monotonic integer-like build number
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

extract_semver() {
  local raw="$1"
  if [[ "$raw" =~ ^v?([0-9]+\.[0-9]+\.[0-9]+)([-+].*)?$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

resolve_raw_version() {
  if [[ -n "${MULTICODEX_BUILD_VERSION:-}" ]]; then
    echo "${MULTICODEX_BUILD_VERSION}"
    return 0
  fi

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git describe --tags --always --dirty --match 'v[0-9]*' 2>/dev/null || git rev-parse --short HEAD
    return 0
  fi

  date +%Y%m%d-%H%M%S
}

artifact_version() {
  local raw_version safe_version
  raw_version="$(resolve_raw_version)"

  # Strip leading "v" when source is a conventional tag.
  raw_version="${raw_version#v}"

  # Keep filename-safe characters only.
  safe_version="$(printf '%s' "$raw_version" | tr -cs 'A-Za-z0-9._-' '-')"
  safe_version="${safe_version#-}"
  safe_version="${safe_version%-}"

  if [[ -z "$safe_version" ]]; then
    safe_version="$(date +%Y%m%d-%H%M%S)"
  fi

  echo "$safe_version"
}

semver_version() {
  local semver=""
  if [[ -n "${MULTICODEX_APP_VERSION:-}" ]]; then
    semver="$(extract_semver "${MULTICODEX_APP_VERSION}" || true)"
  fi

  if [[ -z "$semver" ]] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    semver="$(extract_semver "$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || true)" || true)"
  fi

  if [[ -z "$semver" ]]; then
    semver="$(extract_semver "$(resolve_raw_version)" || true)"
  fi

  if [[ -z "$semver" ]]; then
    semver="0.1.0"
  fi

  echo "$semver"
}

build_number() {
  if [[ -n "${MULTICODEX_BUILD_NUMBER:-}" ]]; then
    if [[ "${MULTICODEX_BUILD_NUMBER}" =~ ^[0-9]+$ ]]; then
      echo "${MULTICODEX_BUILD_NUMBER}"
      return 0
    fi
    die "MULTICODEX_BUILD_NUMBER must be numeric."
  fi

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git rev-list --count HEAD
    return 0
  fi

  echo "1"
}

main() {
  cd "$root_dir"

  case "$mode" in
    artifact)
      artifact_version
      ;;
    semver)
      semver_version
      ;;
    build-number)
      build_number
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      die "unknown mode '$mode'. Use: artifact, semver, build-number"
      ;;
  esac
}

main
