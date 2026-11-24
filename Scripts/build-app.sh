#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
configuration="${1:-release}"
case "$configuration" in
    release|debug) ;;
    *) printf 'Usage: %s [release|debug]\n' "$0" >&2; exit 2 ;;
esac

swift build --configuration "$configuration" --product Miso
binary_dir="$(swift build --configuration "$configuration" --show-bin-path)"
mkdir -p dist
staging="$(mktemp -d "$(pwd)/dist/.build.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/Miso.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Scripts/Info.plist "$app/Contents/Info.plist"
cp assets/MisoMenuBar.svg assets/MisoAppIcon.icns "$app/Contents/Resources/"
install -m 755 "$binary_dir/Miso" "$app/Contents/MacOS/Miso"
codesign --force --sign "${MISO_SIGN_IDENTITY:--}" "$app"
codesign --verify --strict "$app"
ditto "$app" dist/Miso.app
codesign --verify --strict dist/Miso.app
printf '%s\n' "$(pwd)/dist/Miso.app"
