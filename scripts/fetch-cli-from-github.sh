#!/usr/bin/env bash
set -euo pipefail

# Fetches the latest multicodex CLI source from GitHub, builds dist/cli.js,
# and embeds it into the macOS app resources.

repo="${CLI_GITHUB_REPO:-mohammadhmn/multicodex}"
version_input="${CLI_VERSION:-}"
output_path="Sources/MultiCodexMenu/Resources/multicodex-cli.js"

if ! command -v bun >/dev/null 2>&1; then
  echo "Error: bun is required to build multicodex CLI from source."
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required."
  exit 1
fi
if ! command -v tar >/dev/null 2>&1; then
  echo "Error: tar is required."
  exit 1
fi

normalize_tag() {
  local raw="$1"
  if [[ "$raw" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$raw"
    return 0
  fi
  if [[ "$raw" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "v${raw}"
    return 0
  fi
  return 1
}

resolve_latest_tag() {
  local release_json tags_json tag

  release_json="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null || true)"
  if [[ -n "$release_json" ]]; then
    tag="$(printf '%s' "$release_json" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);if(typeof j.tag_name==="string") process.stdout.write(j.tag_name);}catch{}})')"
    if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "$tag"
      return 0
    fi
  fi

  tags_json="$(curl -fsSL "https://api.github.com/repos/${repo}/tags?per_page=30")"
  tag="$(printf '%s' "$tags_json" | node -e '
let s="";
process.stdin.on("data",d=>s+=d).on("end",()=>{
  try {
    const arr = JSON.parse(s);
    const match = Array.isArray(arr) ? arr.find(t => /^v\d+\.\d+\.\d+$/.test(String(t?.name || ""))) : null;
    if (match) process.stdout.write(String(match.name));
  } catch {}
});
')"

  if [[ -z "$tag" ]]; then
    echo "Error: could not resolve latest v* tag from ${repo}."
    exit 1
  fi

  echo "$tag"
}

if [[ -n "$version_input" ]]; then
  if ! tag="$(normalize_tag "$version_input")"; then
    echo "Error: CLI_VERSION must be vMAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH"
    exit 1
  fi
else
  tag="$(resolve_latest_tag)"
fi

echo "Syncing multicodex CLI from GitHub repo ${repo} at tag ${tag}"

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

archive_url="https://github.com/${repo}/archive/refs/tags/${tag}.tar.gz"
curl -fsSL "$archive_url" | tar -xz -C "$tmpdir"

src_dir="$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [[ -z "$src_dir" ]]; then
  echo "Error: failed to unpack CLI source archive for ${tag}."
  exit 1
fi

(
  cd "$src_dir"
  if [[ -f bun.lock ]]; then
    bun install --frozen-lockfile
  else
    bun install
  fi
  bun run build
)

cli_dist_path=""
if [[ -f "$src_dir/dist/cli.js" ]]; then
  cli_dist_path="$src_dir/dist/cli.js"
elif [[ -f "$src_dir/apps/cli/dist/cli.js" ]]; then
  cli_dist_path="$src_dir/apps/cli/dist/cli.js"
else
  echo "Error: expected built file not found at either:"
  echo "  - $src_dir/dist/cli.js"
  echo "  - $src_dir/apps/cli/dist/cli.js"
  exit 1
fi

mkdir -p "$(dirname "$output_path")"
cp "$cli_dist_path" "$output_path"

echo "Bundled CLI written to ${output_path}"
