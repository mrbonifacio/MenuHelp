# MenuHelp

MenuHelp is an open-source macOS menu bar utility for system monitoring,
clipboard history, keyboard cleaning, keeping your Mac awake, external display
brightness, and local system audio transcription.

## Features

| Feature | What it does |
| --- | --- |
| System monitoring | Shows CPU, memory, and disk usage; can be switched on or off. |
| Clipboard history | Stores copied text and images locally, with search and a global shortcut. |
| Keyboard cleaning | Temporarily blocks keyboard input for 30 seconds. |
| Prevent Sleep | Keeps the display on and prevents automatic idle sleep. |
| External display brightness | Controls compatible DDC/CI displays using bundled native helpers. |
| Audio transcription | Converts system playback into timestamped text and automatically saves a TXT file. |
| Preferences | Offers English and Brazilian Portuguese, launch at login, and persistent settings. |

The documentation describes the current source on `main`. **Audio transcription
is available when building the current source; it is not included in the existing
0.2.0 download.** See the [user guide](docs/USAGE.md) for every feature.

## Download and install

[Download the latest release for Mac](https://github.com/mrbonifacio/MenuHelp/releases/latest)

1. Download the universal DMG, open it, and drag **MenuHelp** into **Applications**.
   Alternatively, extract the ZIP and move `MenuHelp.app` into Applications.
2. Open the app from Applications. Its icon appears in the menu bar.
3. Click the icon to open the dashboard; right-click it for **Settings**, audio
   transcription (current source builds), and **Quit**.

Requires **macOS 15.7 or later**, on Apple Silicon or Intel. The app includes its
brightness helpers; no Homebrew, Xcode, or Rosetta installation is needed to use it.

The current free release is ad-hoc signed and **not Apple-notarized**. If macOS
blocks the first launch, attempt to open it, then use **System Settings → Privacy
& Security → Open Anyway** if you trust the download source. See
[Apple's instructions](https://support.apple.com/102445). Managed Macs may restrict
this option. You do not need to disable Gatekeeper.

To update, quit MenuHelp and replace the app in Applications. Local history and
preferences are kept. See [installation instructions](Distribution/INSTALL.txt).

## Quick start

- Turn on **System Monitoring** in the dashboard to view CPU, memory, and disk.
- Enable **Clipboard History**, copy some text, then press **Shift + Command + V**.
  Search, navigate with **↑ / ↓**, and press **Enter** to paste the selected item.
- Enable **Keyboard Cleaning** to block keyboard input for 30 seconds.
- Enable **Prevent Sleep** to keep the Mac and display awake during inactivity.
- Use the brightness slider for each compatible external display.
- In a current source build, open **Audio Transcription**, select the spoken
  language, click **Start Transcription**, then play audio on the Mac. Click
  **Stop and Save** when finished.
- Open **Settings** to configure history retention, shortcuts, language, and
  launch at login. Restart the app after changing its language.

See the [complete user guide and troubleshooting](docs/USAGE.md).

## Permissions and privacy

| Permission | Purpose |
| --- | --- |
| Accessibility | Keyboard cleaning and automatic pasting from clipboard history. |
| Screen & System Audio Recording | Capturing system playback for transcription. |
| Speech Recognition | Recognizing speech locally on this Mac. |

MenuHelp has no accounts, telemetry, or content uploads. Clipboard data is stored
under `~/Library/Application Support/MenuHelp/`. Transcripts are saved under
`~/Documents/MenuHelp/Transcriptions/`. These files have no application-level
encryption. macOS may download a local speech model before first use; audio and
transcripts are processed on the device. The microphone is excluded, and no audio
or video recording files are created. See the [privacy policy](PRIVACY.md).

## Build from source

Requires a Mac with **Xcode 26 or later** and the macOS SDK it includes.

```sh
git clone https://github.com/mrbonifacio/MenuHelp.git
cd MenuHelp
open MenuHelp.xcodeproj
```

Select the **MenuHelp** target and **My Mac**, then run with **Command + R**.
To build without signing:

```sh
xcodebuild \
  -project MenuHelp.xcodeproj \
  -target MenuHelp \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Xcode compiles the bundled helpers from pinned [third-party sources](ThirdParty/README.md)
without downloads: `m1ddc` for Apple Silicon and `ddcctl` for Intel. DDC/CI must be
enabled on the display, and the cable, adapter, or dock must support it.

See [development setup and validation](SETUP.md) for the architecture, tests, and
manual checks.

## Package a release

```sh
bash Scripts/package-release.sh 0.2.0
```

This example packages the current checkout; it does not reproduce the published
0.2.0 tag. Choose a new version before publishing changed code. Output goes to
`dist/<version>/`: a universal DMG, ZIP, installation guide, and checksums. The
script bundles the native helpers and their source/licenses, signs ad-hoc by
default, and verifies the bundle. Developer ID signing and notarization are
optional. See [release instructions](RELEASING.md).

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes. Report security
vulnerabilities privately using the process in [SECURITY.md](SECURITY.md).

## License

MenuHelp is licensed under [MIT](LICENSE). Bundled components retain their own
licenses: m1ddc (MIT) and the separate ddcctl executable (GPL-3.0). Complete helper
sources, build instructions, and notices are included in [ThirdParty](ThirdParty/README.md)
and in the distributed app.
