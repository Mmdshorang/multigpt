set shell := ["bash", "-euo", "pipefail", "-c"]

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
    @just list

list:
    @echo "Common commands:"
    @echo "  just dev               Build + run debug app"
    @echo "  just dmg               Build release DMG"
    @echo "  just ci                Local CI checks"
    @echo "  just doctor            Verify toolchain and codex runtime"
    @echo "  just release minor     Create/push v tag"
    @echo "  just kickoff-release   Patch bump + release tag"
    @echo "  just icons             Regenerate app icon (.icns)"
    @echo "  just clean             Clean build artifacts"

doctor:
    swift --version
    if command -v codex >/dev/null 2>&1; then codex --version; else echo "codex not found in PATH (required at runtime)"; fi
    test -f "{{app_icon_icns}}"
    @echo "doctor: runtime checks passed"

icons:
    bash scripts/generate-app-icon.sh "{{app_iconset}}" "{{app_icon_icns}}"
    @echo "icons: generated {{app_icon_icns}}"

dev:
    just _bundle debug
    pkill -x "{{app_name}}" || true
    open "{{app_bundle}}"

dmg:
    just _bundle release
    mkdir -p "{{dist_dir}}" "{{dmg_staging}}"
    if [[ -d "{{dmg_staging}}" ]]; then find "{{dmg_staging}}" -mindepth 1 -delete; fi
    ditto "{{app_bundle}}" "{{dmg_staging}}/{{app_name}}.app"
    ln -snf /Applications "{{dmg_staging}}/Applications"
    hdiutil create -volname "{{app_name}}" -srcfolder "{{dmg_staging}}" -ov -format UDZO "{{dmg_path}}"
    @echo "Created {{dmg_path}}"

ci:
    just doctor
    bash scripts/swift-safe.sh swift build -c debug
    if [[ -d "Tests" ]]; then bash scripts/swift-safe.sh swift test; else echo "ci: no Swift tests found"; fi

clean:
    swift package clean || true
    swift package reset || true
    rm -rf .build
    if [[ -d "{{build_root}}" ]]; then find "{{build_root}}" -mindepth 1 -delete; fi

release version:
    bash ./scripts/release.sh "{{version}}"

kickoff-release version="patch":
    scripts/release.sh --bump "{{version}}"
