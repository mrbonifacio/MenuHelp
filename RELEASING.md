# Releasing MenuHelp

## Package the current source

On a Mac with Xcode 26 or later, run from the repository root:

```sh
bash Scripts/package-release.sh 0.2.0
```

This packages the current checkout using the supplied version. Choose a new
version for changes after the published 0.2.0 release. The output under
`dist/<version>/` contains a DMG with the app and an Applications shortcut, an
alternative ZIP, an English INSTALL.txt, and SHA256SUMS.txt. Existing packages
are not overwritten; move them elsewhere or choose another version. Temporary
build files are removed automatically.

The app is universal. The bundled helpers are native arm64 (`m1ddc`) and x86_64
(`ddcctl`) executables using macOS libraries only. The Xcode build phase includes
them during normal development builds as well. No Homebrew or build-time download
is required. To inspect an extracted universal app:

```sh
bash Scripts/verify-bundle.sh /path/to/MenuHelp.app
```

Verification checks architectures, signatures, external libraries, localizations,
and bundled source/licenses. It does not prove notarization or hardware brightness
compatibility. Before announcing support, test Intel and Apple Silicon hardware,
first launch after download, preferences, clipboard operations, transcription,
and permission flows.

## Publish on GitHub

Update the marketing/build versions in `MenuHelp.xcodeproj/project.pbxproj` and
prepare English release notes. Build and validate the exact commit being
published, including ThirdParty and Scripts. Do not commit `dist/`.

The following illustrates the existing 0.2.0 naming convention; use a new tag and
version for a new release, and do not replace an existing published tag:

```sh
git tag -a v0.2.0 -m 'MenuHelp 0.2.0'
git push origin v0.2.0
gh release create v0.2.0 \
  dist/0.2.0/MenuHelp-0.2.0-universal.dmg \
  dist/0.2.0/MenuHelp-0.2.0-universal.zip \
  dist/0.2.0/SHA256SUMS.txt dist/0.2.0/INSTALL.txt \
  --repo mrbonifacio/MenuHelp --verify-tag \
  --title 'MenuHelp 0.2.0' --notes-file Distribution/RELEASE-0.2.0.md
```

GitHub's Source code archives correspond to the tag and include the complete
bundled helper sources. Each app also includes
`Contents/Resources/ThirdPartySources.zip` and `Contents/Resources/Licenses/`.

**Actions → Package release → Run workflow** generates packages as downloadable
workflow artifacts without publishing them automatically. Select the intended
commit/tag. Publishing source on main does not update an existing release binary.

## Optional Developer ID signing and notarization

Signing defaults to ad-hoc (`-`), which supports integrity checks but does not
verify the developer's identity or avoid manual Gatekeeper authorization. An Apple
Development certificate does not replace Developer ID for distribution.

With a Developer ID Application certificate and a Keychain profile configured
using `xcrun notarytool store-credentials`, run:

```sh
MENUHELP_SIGN_IDENTITY='Developer ID Application: NAME (TEAMID)' \
MENUHELP_NOTARY_PROFILE='MenuHelp-notary' \
bash Scripts/package-release.sh 0.2.0
```

The script signs helpers before the app, submits it to Apple, staples and
validates the ticket, then creates the packages. It also notarizes and validates
the DMG. Failures stop packaging; do not publish partial artifacts. Update the
installation guide and release notes to describe the actual signing status.
Never add certificates or credentials to Git.

## First launch

Users install only MenuHelp. Builds without notarization may require **System
Settings → Privacy & Security → Open Anyway** after the first launch attempt.
Do not instruct users to disable Gatekeeper globally. See
[Apple Support](https://support.apple.com/102445) and
[Developer ID](https://developer.apple.com/developer-id/).
