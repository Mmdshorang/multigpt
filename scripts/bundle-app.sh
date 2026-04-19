#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-debug}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "${script_dir}/.." && pwd)"

app_name="MultiCodex"
resource_bundle="macos_MultiCodex.bundle"
app_bundle="${root_dir}/build/dist/MultiCodex.app"
default_bundle_id="org.swift.swiftpm.macos.MultiCodex"
app_icon_icns="${root_dir}/Assets/AppIcon.icns"
plist_buddy="/usr/libexec/PlistBuddy"
version_resolver="${root_dir}/scripts/resolve-build-version.sh"

app_semver="0.1.0"
app_build_number="1"
app_build_label="local"

die() {
  echo "Error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

validate_configuration() {
  if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    die "invalid configuration '$configuration' (use: debug|release)"
  fi
}

resolve_versions() {
  if [[ ! -f "$version_resolver" ]]; then
    die "version resolver not found: $version_resolver"
  fi
  app_semver="$(bash "$version_resolver" semver)"
  app_build_number="$(bash "$version_resolver" build-number)"
  app_build_label="$(bash "$version_resolver" artifact)"
}

build_binary() {
  bash "${root_dir}/scripts/swift-safe.sh" swift build -c "$configuration"

  if [[ ! -x "${root_dir}/.build/${configuration}/${app_name}" ]]; then
    die "expected executable not found: .build/${configuration}/${app_name}"
  fi
}

prepare_bundle_dirs() {
  mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"

  if [[ -d "$app_bundle/$resource_bundle" ]]; then
    rm -rf "$app_bundle/$resource_bundle"
  fi

  if [[ -d "$app_bundle/Contents/MacOS" ]]; then
    find "$app_bundle/Contents/MacOS" -mindepth 1 -delete
  fi

  if [[ -d "$app_bundle/Contents/Resources" ]]; then
    find "$app_bundle/Contents/Resources" -mindepth 1 -delete
  fi
}

copy_binary() {
  cp "${root_dir}/.build/${configuration}/${app_name}" "$app_bundle/Contents/MacOS/$app_name"
  chmod +x "$app_bundle/Contents/MacOS/$app_name"
}

copy_resource_bundle_if_present() {
  if [[ -d "${root_dir}/.build/${configuration}/${resource_bundle}" ]]; then
    local target_bundle="$app_bundle/Contents/Resources/${resource_bundle}"
    if [[ -d "$target_bundle" ]]; then
      find "$target_bundle" -mindepth 1 -delete
    fi
    ditto "${root_dir}/.build/${configuration}/${resource_bundle}" "$target_bundle"
  fi
}

upsert_plist_value() {
  local plist_path="$1"
  local key="$2"
  local type="$3"
  local value="$4"

  if "$plist_buddy" -c "Set :${key} ${value}" "$plist_path" >/dev/null 2>&1; then
    return 0
  fi

  "$plist_buddy" -c "Add :${key} ${type} ${value}" "$plist_path"
}

write_info_plist() {
  local plist_path="$app_bundle/Contents/Info.plist"

  rm -f "$plist_path"
  printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0"><dict/></plist>' > "$plist_path"

  upsert_plist_value "$plist_path" "CFBundleDevelopmentRegion" "string" "en"
  upsert_plist_value "$plist_path" "CFBundleExecutable" "string" "$app_name"
  upsert_plist_value "$plist_path" "CFBundleIdentifier" "string" "$default_bundle_id"
  upsert_plist_value "$plist_path" "CFBundleInfoDictionaryVersion" "string" "6.0"
  upsert_plist_value "$plist_path" "CFBundleIconFile" "string" "AppIcon"
  upsert_plist_value "$plist_path" "CFBundleName" "string" "$app_name"
  upsert_plist_value "$plist_path" "CFBundlePackageType" "string" "APPL"
  upsert_plist_value "$plist_path" "CFBundleShortVersionString" "string" "$app_semver"
  upsert_plist_value "$plist_path" "CFBundleVersion" "string" "$app_build_number"
  upsert_plist_value "$plist_path" "LSMinimumSystemVersion" "string" "13.0"
  upsert_plist_value "$plist_path" "MultiCodexBuildLabel" "string" "$app_build_label"

  if [[ "$configuration" == "debug" ]]; then
    upsert_plist_value "$plist_path" "LSUIElement" "bool" "false"
  else
    upsert_plist_value "$plist_path" "LSUIElement" "bool" "true"
  fi
}

copy_icon() {
  if [[ ! -f "$app_icon_icns" ]]; then
    die "expected icon not found: $app_icon_icns"
  fi
  cp "$app_icon_icns" "$app_bundle/Contents/Resources/AppIcon.icns"
}

sign_bundle() {
  # Keep app identity stable across builds so macOS notification/TCC permissions
  # are associated with CFBundleIdentifier instead of transient linker identifiers.
  codesign --force --sign - --deep --identifier "$default_bundle_id" "$app_bundle"
}

main() {
  cd "$root_dir"
  require_command "$plist_buddy"
  require_command codesign
  require_command swift
  validate_configuration
  resolve_versions
  build_binary
  prepare_bundle_dirs
  copy_binary
  copy_resource_bundle_if_present
  write_info_plist
  copy_icon
  sign_bundle
  echo "Created $app_bundle"
}

main
