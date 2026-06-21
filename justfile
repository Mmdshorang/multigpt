set shell := ["bash", "-euo", "pipefail", "-c"]
set windows-shell := ["powershell.exe", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]

app_name := "MultiCodex"
resource_bundle := "macos_MultiCodex.bundle"
build_root := "build"
dist_dir := "build/dist"
dmg_staging := "build/dmg-staging"
app_bundle := "build/dist/MultiCodex.app"
dmg_path := "build/dist/MultiCodex.dmg"
default_bundle_id := "org.swift.swiftpm.macos.MultiCodex"
app_iconset := "Assets/AppIcon.appiconset"
app_icon_icns := "Assets/AppIcon.icns"

_bundle configuration:
    bash scripts/bundle-app.sh "{{configuration}}"

default:
    @just help

help:
    @echo "Common commands:"
    @echo "  just run               Build + run debug app"
    @echo "  just build [debug|release]  Build app bundle"
    @echo "  just win-run           Build + run Windows app"
    @echo "  just win-build [Debug|Release]  Build Windows app"
    @echo "  just win-publish       Publish Windows app to Windows/dist"
    @echo "  just win-publish-self-contained  Publish Windows app with runtime"
    @echo "  just test              Run Swift tests"
    @echo "  just package           Build versioned DMG"
    @echo "  just check             Local verification (doctor + build + test)"
    @echo "  just doctor            Verify toolchain and codex runtime"
    @echo "  just release patch     Create/push release tag"
    @echo "  just icons             Regenerate app icon (.icns)"
    @echo "  just clean             Clean build artifacts"

list:
    @just help

doctor:
    swift --version
    if command -v codex >/dev/null 2>&1; then codex --version; else echo "codex not found in PATH (required at runtime)"; fi
    test -f "{{app_icon_icns}}"
    @echo "doctor: runtime checks passed"

icons:
    bash scripts/generate-app-icon.sh "{{app_iconset}}" "{{app_icon_icns}}"
    @echo "icons: generated {{app_icon_icns}}"

build configuration="debug":
    just _bundle "{{configuration}}"

run:
    just build debug
    pkill -x "{{app_name}}" || true
    open "{{app_bundle}}"

win-build configuration="Debug":
    & .\Windows\build-windows.ps1 -Configuration "{{configuration}}"

win-run configuration="Debug":
    & .\Windows\build-windows.ps1 -Configuration "{{configuration}}" -Run

win-publish:
    & .\Windows\build-windows.ps1 -Publish

win-publish-self-contained:
    & .\Windows\build-windows.ps1 -SelfContained

test:
    if [[ -d "Tests" ]]; then bash scripts/swift-safe.sh swift test; else echo "test: no Swift tests found"; fi

package:
    #!/usr/bin/env bash
    set -euo pipefail
    just _bundle release
    mkdir -p "{{dist_dir}}" "{{dmg_staging}}"
    if [[ -d "{{dmg_staging}}" ]]; then find "{{dmg_staging}}" -mindepth 1 -delete; fi
    ditto "{{app_bundle}}" "{{dmg_staging}}/{{app_name}}.app"
    ln -snf /Applications "{{dmg_staging}}/Applications"
    build_version="$(bash scripts/resolve-build-version.sh)"
    dmg_versioned_path="{{dist_dir}}/{{app_name}}-${build_version}.dmg"
    hdiutil create -volname "{{app_name}}" -srcfolder "{{dmg_staging}}" -ov -format UDZO "${dmg_versioned_path}"
    ln -snf "$(basename "${dmg_versioned_path}")" "{{dmg_path}}"
    echo "Created ${dmg_versioned_path}"
    echo "Updated latest link {{dmg_path}} -> $(basename "${dmg_versioned_path}")"

check:
    just doctor
    bash scripts/swift-safe.sh swift build -c debug
    just test

clean:
    swift package clean || true
    swift package reset || true
    rm -rf .build
    if [[ -d "{{build_root}}" ]]; then find "{{build_root}}" -mindepth 1 -delete; fi

release target="patch":
    bash ./scripts/release.sh "{{target}}"
