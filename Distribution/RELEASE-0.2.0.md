# MenuHelp 0.2.0 — single-app installation

## Download and install

Download **MenuHelp-0.2.0-universal.dmg**, open it, and drag MenuHelp into
Applications. Alternatively, extract the ZIP and move the app into Applications.
Requires **macOS 15.7 or later**, on Apple Silicon or Intel.

This release is ad-hoc signed and **not Apple-notarized**. If the first launch is
blocked, attempt to open the app, then use **System Settings → Privacy & Security
→ Open Anyway** if you trust the download source. See
[Apple's instructions](https://support.apple.com/102445). You do not need to
disable Gatekeeper or install extra tools.

## Changes in this release

- Bundled DDC/CI control: native m1ddc on Apple Silicon and ddcctl on Intel.
- No Homebrew, Xcode, or Rosetta installation required to use the app.
- English and Brazilian Portuguese with a language selector in Settings.
- Launch at login and persistent preferences.
- Prevent Sleep keeps the system and display awake during inactivity.
- Menu bar context menu with Settings and Quit actions.

The app also provides system monitoring, local clipboard history with
Shift + Command + V, and 30-second keyboard cleaning. Audio transcription was
added after this release and is not included in its binaries.

Hardware brightness requires a compatible DDC/CI monitor and connection, including
the port, cable, and dock. Accessibility is required for automatic pasting and
keyboard cleaning. The app operates locally without telemetry. Clipboard history
can contain sensitive data and has no application-level encryption; see the
[privacy policy](https://github.com/mrbonifacio/MenuHelp/blob/main/PRIVACY.md).

Validation recorded for this release: universal build, DMG integrity, ad-hoc
signatures, absence of external libraries, and brightness reads from an AOC 27G4
on Apple Silicon using only the bundled helper. Execution on Intel and first
launch on another Mac with Gatekeeper still require independent hardware testing.

## Sources, licenses, and verification

`SHA256SUMS.txt` contains download checksums. The release's **Source code** archive
contains complete corresponding MenuHelp and helper sources, including ThirdParty
and Scripts. Helper sources, licenses, and the build script also ship inside the
app under `Contents/Resources/ThirdPartySources.zip` and
`Contents/Resources/Licenses/`.

MenuHelp and m1ddc are MIT-licensed. The separate ddcctl executable is GPL-3.0.
