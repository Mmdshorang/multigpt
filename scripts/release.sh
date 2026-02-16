#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Kickstart a new MultiCodex release.

Usage:
  scripts/release.sh --version <vX.Y.Z>
  scripts/release.sh --version <X.Y.Z>
  scripts/release.sh --bump <major|minor|patch>
  scripts/release.sh <vX.Y.Z>
  scripts/release.sh <X.Y.Z>
  scripts/release.sh <major|minor|patch>

Examples:
  scripts/release.sh --version v0.2.3
  scripts/release.sh --version 0.2.3
  scripts/release.sh --bump patch
  scripts/release.sh v0.2.3
  scripts/release.sh 0.2.3
  scripts/release.sh patch
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_clean_main_branch() {
  local current_branch
  current_branch="$(git rev-parse --abbrev-ref HEAD)"
  [[ "$current_branch" == "main" ]] || die "release must be created from 'main' (current: $current_branch)."

  if [[ -n "$(git status --porcelain)" ]]; then
    die "working tree is not clean. Commit or stash your changes first."
  fi
}

normalize_version_input() {
  local raw="$1"
  if [[ "$raw" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    echo "v${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$raw" =~ ^([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    echo "v${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

latest_version_tag() {
  local latest_tag legacy_tag
  latest_tag="$(git tag --list 'v*' --sort=-v:refname | head -n1 || true)"
  if [[ -n "$latest_tag" ]]; then
    echo "$latest_tag"
    return 0
  fi

  # Backward-compat: migrate from legacy macos-v tags if present.
  legacy_tag="$(git tag --list 'macos-v*' --sort=-v:refname | head -n1 || true)"
  if [[ "$legacy_tag" =~ ^macos-v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    echo "v${BASH_REMATCH[1]}"
    return 0
  fi

  echo "v0.0.0"
}

next_version_from_bump() {
  local bump="$1"
  local latest_tag major minor patch

  latest_tag="$(latest_version_tag)"

  if [[ ! "$latest_tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    die "latest tag '$latest_tag' does not match vMAJOR.MINOR.PATCH"
  fi

  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  patch="${BASH_REMATCH[3]}"

  case "$bump" in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
    *)
      die "bump must be one of: major, minor, patch"
      ;;
  esac

  echo "v${major}.${minor}.${patch}"
}

parse_args() {
  mode=""
  input=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        [[ $# -ge 2 ]] || die "missing value for --version"
        [[ -z "$mode" ]] || die "unexpected argument '$1'"
        mode="version"
        input="$2"
        shift 2
        ;;
      --bump)
        [[ $# -ge 2 ]] || die "missing value for --bump"
        [[ -z "$mode" ]] || die "unexpected argument '$1'"
        mode="bump"
        input="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        [[ -z "$mode" && -z "$input" ]] || die "unexpected argument '$1'"
        input="$1"
        shift
        ;;
    esac
  done

  [[ -n "$input" ]] || {
    usage
    die "missing value."
  }
}

resolve_version() {
  local mode="$1"
  local input="$2"

  if [[ "$mode" == "version" ]]; then
    normalize_version_input "$input" || die "--version must match one of: vMAJOR.MINOR.PATCH, MAJOR.MINOR.PATCH"
    return 0
  fi

  if [[ "$mode" == "bump" ]]; then
    next_version_from_bump "$input"
    return 0
  fi

  if normalize_version_input "$input" >/dev/null; then
    normalize_version_input "$input"
  else
    next_version_from_bump "$input"
  fi
}

ensure_tag_available() {
  local version="$1"

  if git rev-parse "$version" >/dev/null 2>&1; then
    die "tag ${version} already exists locally."
  fi

  if git ls-remote --tags origin "refs/tags/${version}" | grep -q "$version"; then
    die "tag ${version} already exists on origin."
  fi
}

main() {
  command -v git >/dev/null 2>&1 || die "'git' is required."

  if [[ $# -eq 0 ]]; then
    usage
    exit 0
  fi

  parse_args "$@"
  require_clean_main_branch

  version="$(resolve_version "$mode" "$input")"

  echo "Preparing release: ${version}"

  git fetch --tags
  ensure_tag_available "$version"

  git tag -a "$version" -m "Release ${version}"
  git push origin "$version"

  echo "Release created: ${version}"
  echo "Tag pushed. GitHub Actions will build DMG and publish the release."
}

main "$@"
