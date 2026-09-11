#!/bin/bash
# Free/ad-hoc by default. Optional Developer ID + notarization via Keychain profile.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
version="${1:-0.2.0}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Expected version X.Y.Z' >&2; exit 1; }
identity="${MENUHELP_SIGN_IDENTITY:--}"
notary_profile="${MENUHELP_NOTARY_PROFILE:-}"
if [[ -n "$notary_profile" && "$identity" != 'Developer ID Application:'* ]]; then
    echo 'Notarization requires MENUHELP_SIGN_IDENTITY=Developer ID Application: ...' >&2
    exit 1
fi
output="$task_root/dist/$version"
mkdir -p "$output"
for filename in "MenuHelp-$version-universal.dmg" "MenuHelp-$version-universal.zip" SHA256SUMS.txt; do
    [[ ! -e "$output/$filename" ]] || { echo "Already exists: $output/$filename (use a new version or move previous artifacts)." >&2; exit 1; }
done
task_work="$(mktemp -d "${TMPDIR:-/tmp}/MenuHelpRelease.XXXXXX")"
trap 'rm -rf "$task_work"' EXIT
final_output="$output"
output="$task_work/artifacts"
mkdir -p "$output"

xcodebuild -quiet -project MenuHelp.xcodeproj -scheme MenuHelp \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$task_work/DerivedData" ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO MARKETING_VERSION="$version" build
mkdir -p "$task_work/image"
app="$task_work/image/MenuHelp.app"
ditto "$task_work/DerivedData/Build/Products/Release/MenuHelp.app" "$app"
sign_options=(--force --options runtime --sign "$identity")
if [[ "$identity" != - ]]; then sign_options+=(--timestamp); fi
for helper in m1ddc ddcctl; do
    codesign "${sign_options[@]}" "$app/Contents/Helpers/$helper"
done
codesign "${sign_options[@]}" "$app"
if [[ -n "$notary_profile" ]]; then
    ditto -c -k --norsrc --keepParent "$app" "$task_work/notarize.zip"
    xcrun notarytool submit "$task_work/notarize.zip" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
fi
bash Scripts/verify-bundle.sh "$app"
ln -s /Applications "$task_work/image/Applications"
cp Distribution/INSTALL.txt "$task_work/image/INSTALL.txt"
cp Distribution/INSTALL.txt "$output/INSTALL.txt"
ditto -c -k --norsrc --keepParent "$app" "$output/MenuHelp-$version-universal.zip"
hdiutil create -volname "MenuHelp $version" -srcfolder "$task_work/image" \
    -format UDZO -fs HFS+ "$output/MenuHelp-$version-universal.dmg"
if [[ "$identity" != - ]]; then
    codesign "${sign_options[@]}" "$output/MenuHelp-$version-universal.dmg"
fi
if [[ -n "$notary_profile" ]]; then
    xcrun notarytool submit "$output/MenuHelp-$version-universal.dmg" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$output/MenuHelp-$version-universal.dmg"
    xcrun stapler validate "$output/MenuHelp-$version-universal.dmg"
fi
hdiutil verify "$output/MenuHelp-$version-universal.dmg"
cd "$output"
shasum -a 256 "MenuHelp-$version-universal.dmg" "MenuHelp-$version-universal.zip" INSTALL.txt > SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
mv "$output/MenuHelp-$version-universal.dmg" "$output/MenuHelp-$version-universal.zip" \
    "$output/INSTALL.txt" "$output/SHA256SUMS.txt" "$final_output/"
cd "$task_root"
echo "Release created: $final_output"
if [[ -z "$notary_profile" ]]; then
    echo 'Not notarized: macOS may require Privacy & Security > Open Anyway on first launch.'
fi
