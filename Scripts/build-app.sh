#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
configuration="${1:-release}"
case "$configuration" in
    release|debug) ;;
    *) printf 'Usage: %s [release|debug]\n' "$0" >&2; exit 2 ;;
esac

output="${MISO_BUILD_OUTPUT:-dist}"
identity="${MISO_SIGN_IDENTITY:--}"
repository="${MISO_RELEASE_REPOSITORY:-}"
public_key="${MISO_SPARKLE_PUBLIC_KEY:-}"
sign_args=(--force --sign "$identity")
swift_args=(--configuration "$configuration" --arch arm64)
if [[ -n "$repository" || -n "$public_key" ]]; then
    if [[ ! "$repository" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ || -z "$public_key" ||
          "$configuration" != release || "$identity" == - ]]; then
        printf 'Updates require an owner/repo, a Sparkle public key, and a distribution signing identity.\n' >&2
        exit 2
    fi
    sign_args+=(--options runtime --timestamp)
    swift_args+=(--force-resolved-versions)
fi

swift build "${swift_args[@]}" --product Miso
binary_dir="$(swift build "${swift_args[@]}" --show-bin-path)"
mkdir -p "$output"
staging="$(mktemp -d "$output/.build.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

app="$staging/Miso.app"
framework="$app/Contents/Frameworks/Sparkle.framework"
plist="$app/Contents/Info.plist"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources"
cp Scripts/Info.plist "$plist"
cp assets/MisoMenuBar.svg assets/MisoAppIcon.icns "$app/Contents/Resources/"
if [[ -n "$repository" ]]; then
    plutil -insert SUFeedURL -string "https://github.com/$repository/releases/latest/download/appcast.xml" "$plist"
    plutil -insert SUPublicEDKey -string "$public_key" "$plist"
    plutil -insert SUEnableAutomaticChecks -bool YES "$plist"
    plutil -insert SUAllowsAutomaticUpdates -bool NO "$plist"
    plutil -insert SUVerifyUpdateBeforeExtraction -bool YES "$plist"
    plutil -insert SURequireSignedFeed -bool YES "$plist"
fi

install -m 755 "$binary_dir/Miso" "$app/Contents/MacOS/Miso"
ditto "$binary_dir/Sparkle.framework" "$framework"
# Installer and downloader XPC services are used by sandboxed apps.
rm -r "$framework/Versions/Current/XPCServices"
rm "$framework/XPCServices"
codesign "${sign_args[@]}" "$framework/Versions/Current/Autoupdate"
codesign "${sign_args[@]}" "$framework/Versions/Current/Updater.app"
codesign "${sign_args[@]}" "$framework"
codesign "${sign_args[@]}" "$app"
codesign --verify --deep --strict "$app"

# A fresh bundle avoids carrying files from a previous Sparkle version.
if [[ -e "$output/Miso.app" ]]; then mv "$output/Miso.app" "$staging/previous.app"; fi
if ! mv "$app" "$output/Miso.app"; then
    if [[ -e "$staging/previous.app" ]]; then mv "$staging/previous.app" "$output/Miso.app"; fi
    exit 1
fi
printf '%s\n' "$(cd "$output" && pwd)/Miso.app"
