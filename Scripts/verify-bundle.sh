#!/bin/bash
set -euo pipefail
app="${1:?Usage: bash Scripts/verify-bundle.sh MenuHelp.app}"
[[ -d "$app/Contents" ]] || { echo "Missing app: $app" >&2; exit 1; }
codesign --verify --deep --strict --verbose=2 "$app"
for architecture in arm64 x86_64; do
    lipo "$app/Contents/MacOS/MenuHelp" -verify_arch "$architecture"
done
lipo "$app/Contents/Helpers/m1ddc" -verify_arch arm64
lipo "$app/Contents/Helpers/ddcctl" -verify_arch x86_64
for binary in "$app/Contents/MacOS/MenuHelp" "$app/Contents/Helpers/m1ddc" "$app/Contents/Helpers/ddcctl"; do
    [[ -x "$binary" ]] || exit 1
    # Every dynamically linked dependency must ship with macOS.
    unexpected="$(otool -L "$binary" | awk '/^[[:space:]]/ {print $1}' | awk '!/^\/System\/Library\// && !/^\/usr\/lib\//')"
    [[ -z "$unexpected" ]] || { echo "External dependencies in $binary: $unexpected" >&2; exit 1; }
    codesign --verify --strict "$binary"
done
for language in en pt-BR; do
    plutil -lint "$app/Contents/Resources/$language.lproj/Localizable.strings"
done
for license in MenuHelp-MIT.txt m1ddc-MIT.txt ddcctl-GPL-3.0.txt ThirdParty.md; do
    test -s "$app/Contents/Resources/Licenses/$license"
done
unzip -tq "$app/Contents/Resources/ThirdPartySources.zip"
for file in ThirdParty/ddcctl/src/DDC.c ThirdParty/m1ddc/sources/m1ddc.m Scripts/build-ddc.sh; do
    unzip -p "$app/Contents/Resources/ThirdPartySources.zip" "$file" | wc -c | awk '$1 == 0 {exit 1}'
done
echo 'Verified: universal app, native bundled helpers, licenses, sources, no external libraries.'
