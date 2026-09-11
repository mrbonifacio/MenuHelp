#!/bin/bash
# Compile the vendored CLIs and include their corresponding sources/licenses.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
output="${1:?Usage: bash Scripts/build-ddc.sh OUTPUT_DIRECTORY}"
sdk="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
deployment="${MACOSX_DEPLOYMENT_TARGET:-15.7}"
mkdir -p "$output/Helpers" "$output/Licenses"
task_work="$(mktemp -d "${TMPDIR:-/tmp}/MenuHelpDDC.XXXXXX")"
trap 'rm -rf "$task_work"' EXIT

xcrun --sdk macosx clang -arch arm64 -isysroot "$sdk" \
    -mmacosx-version-min="$deployment" -O2 -fmodules \
    -fmodules-cache-path="$task_work/modules" \
    -I "$task_root/ThirdParty/m1ddc/headers" \
    "$task_root/ThirdParty/m1ddc/sources/i2c.m" \
    "$task_root/ThirdParty/m1ddc/sources/ioregistry.m" \
    "$task_root/ThirdParty/m1ddc/sources/m1ddc.m" \
    -framework CoreDisplay -framework Foundation -framework IOKit \
    -framework ApplicationServices -o "$output/Helpers/m1ddc"

xcrun --sdk macosx clang -arch x86_64 -isysroot "$sdk" \
    -mmacosx-version-min="$deployment" -O2 \
    "$task_root/ThirdParty/ddcctl/src/DDC.c" \
    "$task_root/ThirdParty/ddcctl/src/ddcctl.m" \
    -lobjc -framework IOKit -framework AppKit -framework Foundation \
    -framework ApplicationServices -o "$output/Helpers/ddcctl"

cp "$task_root/ThirdParty/m1ddc/LICENSE" "$output/Licenses/m1ddc-MIT.txt"
cp "$task_root/ThirdParty/ddcctl/LICENSE" "$output/Licenses/ddcctl-GPL-3.0.txt"
cp "$task_root/ThirdParty/README.md" "$output/Licenses/ThirdParty.md"
mkdir -p "$task_work/corresponding-source/Scripts"
cp -R "$task_root/ThirdParty" "$task_work/corresponding-source/ThirdParty"
cp "$0" "$task_work/corresponding-source/Scripts/build-ddc.sh"
ditto -c -k --norsrc "$task_work/corresponding-source" "$output/ThirdPartySources.zip"

# Xcode development/archive builds also sign nested code before the main app.
# package-release.sh explicitly re-signs both helpers and the app for release.
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [[ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]]; then
    for helper in m1ddc ddcctl; do
        codesign --force --options runtime --sign "${identity:--}" "$output/Helpers/$helper"
    done
fi
