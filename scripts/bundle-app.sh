#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-debug}"
app_name="MultiCodex"
resource_bundle="macos_MultiCodexMenu.bundle"
app_bundle="build/dist/MultiCodex.app"
default_bundle_id="org.swift.swiftpm.macos.MultiCodex"
app_icon_icns="Assets/AppIcon.icns"

validate_configuration() {
  if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    echo "Invalid configuration: $configuration (use debug|release)"
    exit 2
  fi
}

build_binary() {
  swift build -c "$configuration"

  if [[ ! -x ".build/$configuration/$app_name" ]]; then
    echo "Expected executable not found: .build/$configuration/$app_name"
    exit 1
  fi

  if [[ ! -f "$app_icon_icns" ]]; then
    echo "Expected icon not found: $app_icon_icns"
    exit 1
  fi
}

prepare_bundle_dirs() {
  mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"

  if [[ -d "$app_bundle/Contents/MacOS" ]]; then
    find "$app_bundle/Contents/MacOS" -mindepth 1 -delete
  fi

  if [[ -d "$app_bundle/Contents/Resources" ]]; then
    find "$app_bundle/Contents/Resources" -mindepth 1 -delete
  fi
}

copy_binary() {
  cp ".build/$configuration/$app_name" "$app_bundle/Contents/MacOS/$app_name"
  chmod +x "$app_bundle/Contents/MacOS/$app_name"
}

copy_resource_bundle_if_present() {
  if [[ -d ".build/$configuration/$resource_bundle" ]]; then
    if [[ -d "$app_bundle/$resource_bundle" ]]; then
      find "$app_bundle/$resource_bundle" -mindepth 1 -delete
    fi
    ditto ".build/$configuration/$resource_bundle" "$app_bundle/$resource_bundle"
  fi
}

write_info_plist() {
  local plist_path="$app_bundle/Contents/Info.plist"

  rm -f "$plist_path"
  printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0"><dict/></plist>' > "$plist_path"

  /usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string en" "$plist_path"
  /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $app_name" "$plist_path"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $default_bundle_id" "$plist_path"
  /usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$plist_path"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$plist_path"
  /usr/libexec/PlistBuddy -c "Add :CFBundleName string $app_name" "$plist_path"
  /usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$plist_path"
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 0.1.0" "$plist_path"
  /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$plist_path"
  /usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 13.0" "$plist_path"

  if [[ "$configuration" == "debug" ]]; then
    /usr/libexec/PlistBuddy -c "Add :LSUIElement bool false" "$plist_path"
  else
    /usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$plist_path"
  fi
}

copy_icon() {
  cp "$app_icon_icns" "$app_bundle/Contents/Resources/AppIcon.icns"
}

main() {
  validate_configuration
  build_binary
  prepare_bundle_dirs
  copy_binary
  copy_resource_bundle_if_present
  write_info_plist
  copy_icon
  echo "Created $app_bundle"
}

main
