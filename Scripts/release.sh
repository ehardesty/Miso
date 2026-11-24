#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
command="${1:-}"
repository="${2:-}"
initial="${3:-}"
if [[ "$#" -lt 2 || "$#" -gt 3 || ! "$repository" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ||
      ( "$command" != prepare && "$command" != stage ) || ( "$#" -eq 3 && "$initial" != --initial ) ]]; then
    printf 'Usage: %s {prepare|stage} OWNER/REPO [--initial]\n' "$0" >&2
    exit 2
fi

fail() { printf '%s\n' "$*" >&2; exit 1; }
version="$(plutil -extract CFBundleShortVersionString raw Scripts/Info.plist)"
build="$(plutil -extract CFBundleVersion raw Scripts/Info.plist)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[1-9][0-9]*$ ]] ||
    fail 'Set a three-part release version and an increasing integer build in Scripts/Info.plist.'
git diff --quiet HEAD || fail 'Commit tracked changes before preparing or staging a release.'
untracked="$(git ls-files --others -- 'Package*.swift' Package.resolved Scripts Sources)"
[[ -z "$untracked" ]] || fail "Commit or remove untracked release inputs:
$untracked"
git ls-files --error-unmatch Package.resolved >/dev/null || fail 'Commit Package.resolved before releasing.'

tag="v$version"
commit="$(git rev-parse HEAD)"
tools="$PWD/.build/artifacts/sparkle/Sparkle/bin"
account="${MISO_SPARKLE_ACCOUNT:-miso}"
base_url="https://github.com/$repository/releases"
folder="$PWD/dist/releases/$version"
zip_name="Miso-$version-arm64.zip"
mkdir -p dist/releases
scratch="$(mktemp -d "$PWD/dist/releases/.release.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

developer_id_team() {
    local signing_info team
    signing_info="$(codesign -dv --verbose=4 "$1" 2>&1)" ||
        fail "Could not read the signature for $2: $signing_info"
    team="$(sed -n 's/^TeamIdentifier=//p' <<< "$signing_info")"
    [[ "$signing_info" == *"Authority=Developer ID Application:"* && "$team" =~ ^[A-Z0-9]{10}$ ]] ||
        fail "$2 must be signed with Developer ID Application."
    printf '%s\n' "$team"
}

previous_team() {
    local http_status previous previous_url previous_signature
    http_status="$(curl --silent --show-error --location --output "$scratch/latest.xml" --write-out '%{http_code}' \
        --max-time 30 "$base_url/latest/download/appcast.xml")" || fail 'Could not fetch the Latest appcast.'
    case "$http_status" in
        200)
            [[ -z "$initial" ]] || fail 'This repository already has a public update feed. Omit --initial.'
            ;;
        404)
            [[ "$initial" == --initial ]] || fail 'Latest has no update feed. Use --initial only to publish the first Sparkle release.'
            return
            ;;
        *) fail "Could not read the Latest appcast (HTTP $http_status)." ;;
    esac

    "$tools/sign_update" --account "$account" --verify "$scratch/latest.xml" >&2 ||
        fail 'Latest appcast does not verify with the configured Sparkle key.'
    previous="$(python3 Scripts/verify-update.py previous-release "$scratch/latest.xml" "$build" "$repository")" ||
        return 1
    IFS=$'\t' read -r previous_url previous_signature <<< "$previous"
    curl --fail --silent --show-error --location --max-time 120 --output "$scratch/previous.zip" "$previous_url" ||
        fail 'Could not fetch the previous release ZIP.'
    "$tools/sign_update" --account "$account" --verify "$scratch/previous.zip" "$previous_signature" >&2 ||
        fail 'Previous release ZIP does not match its signature.'
    ditto -x -k "$scratch/previous.zip" "$scratch/previous" || return 1
    codesign --verify --deep --strict "$scratch/previous/Miso.app" || return 1
    developer_id_team "$scratch/previous/Miso.app" "Previous release"
}

require_same_team() {
    local team
    team="$(developer_id_team "$1" "New release")"
    [[ -z "$expected_team" || "$team" == "$expected_team" ]] ||
        fail "Developer ID team changed from $expected_team to $team."
}

read_public_key() {
    "$tools/generate_keys" --account "$account" -p
}

verify_assets() {
    local assets="$1"
    local key="$2"
    local signature app
    signature="$(python3 Scripts/verify-update.py verify "$assets/$zip_name" "$assets/appcast.xml" \
        "$repository" "$version" "$build" "$key")"
    "$tools/sign_update" --account "$account" --verify "$assets/$zip_name" "$signature"
    "$tools/sign_update" --account "$account" --verify "$assets/appcast.xml"

    mkdir -p "$scratch/verify"
    ditto -x -k "$assets/$zip_name" "$scratch/verify"
    app="$scratch/verify/Miso.app"
    [[ "$(lipo -archs "$app/Contents/MacOS/Miso")" == arm64 ]] || fail 'Expected an Apple Silicon app.'
    codesign --verify --deep --strict "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
}

if [[ "$command" == prepare ]]; then
    : "${MISO_SIGN_IDENTITY:?Set MISO_SIGN_IDENTITY to your Developer ID Application identity.}"
    : "${MISO_NOTARY_PROFILE:?Set MISO_NOTARY_PROFILE to your notarytool Keychain profile.}"
    [[ ! -e "$folder" ]] || fail "Prepared release already exists at $folder."
    swift package --force-resolved-versions resolve
    public_key="$(read_public_key)"
    expected_team="$(previous_team)"
    mkdir "$scratch/assets"
    MISO_BUILD_OUTPUT="$scratch/build" MISO_RELEASE_REPOSITORY="$repository" \
        MISO_SPARKLE_PUBLIC_KEY="$public_key" Scripts/build-app.sh release
    app="$scratch/build/Miso.app"
    require_same_team "$app"
    ditto -c -k --norsrc --noextattr --keepParent "$app" "$scratch/notarize.zip"
    xcrun notarytool submit "$scratch/notarize.zip" --keychain-profile "$MISO_NOTARY_PROFILE" \
        --wait --output-format json > "$scratch/notary.json"
    if [[ "$(plutil -extract status raw "$scratch/notary.json")" != Accepted ]]; then
        cat "$scratch/notary.json" >&2
        fail 'Apple did not accept the notarization submission.'
    fi
    xcrun stapler staple "$app"
    ditto -c -k --norsrc --noextattr --keepParent "$app" "$scratch/assets/$zip_name"
    "$tools/generate_appcast" --account "$account" --maximum-deltas 0 --maximum-versions 1 \
        --link "$base_url/tag/$tag" --download-url-prefix "$base_url/download/$tag/" "$scratch/assets"
    verify_assets "$scratch/assets" "$public_key"
    printf '%s\n' "$commit" > "$scratch/assets/source-commit"
    python3 -c 'import os, sys; os.rename(*sys.argv[1:])' "$scratch/assets" "$folder"
    printf 'Prepared verified release assets in %s\n' "$folder"
else
    [[ -f "$folder/source-commit" ]] || fail "Prepare the release first. No artifacts found at $folder."
    [[ "$(cat "$folder/source-commit")" == "$commit" ]] ||
        fail 'The prepared artifacts were built from a different commit.'
    private_repository="$(gh api "repos/$repository" --jq .private)"
    [[ "$private_repository" == false ]] || fail 'Sparkle needs a public release repository.'
    tag_commit="$(gh api "repos/$repository/commits/tags/$tag" --jq .sha)" ||
        fail "Could not resolve $tag on GitHub. Check that it was pushed."
    [[ "$tag_commit" == "$commit" ]] || fail "Push $tag at the commit used to build this release."
    swift package --force-resolved-versions resolve
    public_key="$(read_public_key)"
    expected_team="$(previous_team)"
    verify_assets "$folder" "$public_key"
    require_same_team "$scratch/verify/Miso.app"

    url="$(gh release create "$tag" "$folder/$zip_name" "$folder/appcast.xml" \
        --repo "$repository" --verify-tag --draft --title "Miso $version" --generate-notes)"
    printf 'Draft created: %s\n' "$url"
    mkdir "$scratch/download"
    if ! gh release download "$tag" --repo "$repository" --dir "$scratch/download" ||
       ! cmp "$folder/$zip_name" "$scratch/download/$zip_name" ||
       ! cmp "$folder/appcast.xml" "$scratch/download/appcast.xml"; then
        fail 'Could not verify the uploaded assets. Keep the draft unpublished.'
    fi
    printf 'Draft matches the signed assets: %s\n' "$url"
fi
