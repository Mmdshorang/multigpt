#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Kickstart a new MultiCodex macOS release.

Usage:
  scripts/release.sh --version <macos-vX.Y.Z>
  scripts/release.sh --version <vX.Y.Z>
  scripts/release.sh --version <X.Y.Z>
  scripts/release.sh --bump <major|minor|patch>
  scripts/release.sh <macos-vX.Y.Z>
  scripts/release.sh <vX.Y.Z>
  scripts/release.sh <X.Y.Z>
  scripts/release.sh <major|minor|patch>

Examples:
  scripts/release.sh --version macos-v0.2.3
  scripts/release.sh --version v0.2.3
  scripts/release.sh --version 0.2.3
  scripts/release.sh --bump patch
  scripts/release.sh macos-v0.2.3
  scripts/release.sh v0.2.3
  scripts/release.sh 0.2.3
  scripts/release.sh patch
USAGE
}

if [[ "${1:-}" == "" ]] || [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v git >/dev/null 2>&1; then
  echo "Error: 'git' is required."
  exit 1
fi

current_branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$current_branch" != "main" ]]; then
  echo "Error: release must be created from 'main' (current: $current_branch)."
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Error: working tree is not clean. Commit or stash your changes first."
  exit 1
fi

mode=""
input=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      mode="version"
      input="${2:-}"
      shift 2
      ;;
    --bump)
      mode="bump"
      input="${2:-}"
      shift 2
      ;;
    *)
      if [[ -n "$mode" ]]; then
        echo "Error: unexpected argument '$1'"
        usage
        exit 1
      fi
      input="$1"
      shift
      ;;
  esac
done

if [[ -z "$input" ]]; then
  echo "Error: missing value."
  usage
  exit 1
fi

next_version_from_bump() {
  local bump="$1"
  local latest_tag latest major minor patch

  latest_tag="$(git tag --list 'macos-v*' --sort=-v:refname | head -n1 || true)"
  if [[ -z "$latest_tag" ]]; then
    latest_tag="macos-v0.0.0"
  fi

  if [[ ! "$latest_tag" =~ ^macos-v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Error: latest tag '$latest_tag' does not match macos-vMAJOR.MINOR.PATCH"
    exit 1
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
      echo "Error: bump must be one of: major, minor, patch"
      exit 1
      ;;
  esac

  echo "macos-v${major}.${minor}.${patch}"
}

normalize_version_input() {
  local raw="$1"
  if [[ "$raw" =~ ^macos-v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$raw"
    return 0
  fi
  if [[ "$raw" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    echo "macos-v${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$raw" =~ ^([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    echo "macos-v${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

if [[ "$mode" == "version" ]]; then
  if ! version="$(normalize_version_input "$input")"; then
    echo "Error: --version must match one of: macos-vMAJOR.MINOR.PATCH, vMAJOR.MINOR.PATCH, MAJOR.MINOR.PATCH"
    exit 1
  fi
elif [[ "$mode" == "bump" ]]; then
  version="$(next_version_from_bump "$input")"
else
  if version="$(normalize_version_input "$input")"; then
    :
  else
    version="$(next_version_from_bump "$input")"
  fi
fi

echo "Preparing release: ${version}"

git fetch --tags

if git rev-parse "${version}" >/dev/null 2>&1; then
  echo "Error: tag ${version} already exists locally."
  exit 1
fi

if git ls-remote --tags origin "refs/tags/${version}" | grep -q "${version}"; then
  echo "Error: tag ${version} already exists on origin."
  exit 1
fi

git tag -a "${version}" -m "Release ${version}"
git push origin "${version}"
echo "Release created: ${version}"
echo "Tag pushed. GitHub Actions will build DMG and publish the release."
