# Development setup

## Requirements and first run

Use a Mac with Xcode 26 or later and its macOS SDK. The deployment target is
macOS 15.7. Open `MenuHelp.xcodeproj`, select the **MenuHelp** target and **My Mac**,
and run with **Command + R**. Choose a signing team only if you need a locally
signed build; never commit Team IDs or certificates.

The app uses `LSUIElement`, so it appears in the menu bar without a Dock icon.

```sh
xcodebuild \
  -project MenuHelp.xcodeproj \
  -target MenuHelp \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Source layout

| Path | Responsibility |
| --- | --- |
| `MenuHelp/MenuBarController.swift` | Menu bar dashboard, windows, and actions. |
| `MenuHelp/Dashboard/` | System metrics, keyboard cleaning, and idle sleep prevention. |
| `MenuHelp/Clipboard/` | Clipboard capture, storage, search, and history window. |
| `MenuHelp/Shortcuts/` | Global clipboard shortcut registration. |
| `MenuHelp/Brightness/` | External display discovery and bundled helper execution. |
| `MenuHelp/Preferences/` | Preferences, interface language, and launch at login. |
| `MenuHelp/Transcription/` | System audio capture, speech backends, timestamps, and TXT storage. |
| `MenuHelp/en.lproj/`, `MenuHelp/pt-BR.lproj/` | Interface and permission localizations. |
| `Configuration/` | App permission usage descriptions. |
| `Scripts/` | Helper builds, packaging, verification, and transcription tests. |
| `ThirdParty/` | Pinned brightness helper sources and licenses. |

## Permissions during development

macOS associates permission grants with the app's signature and path. After
changing either, you may need to remove and re-add MenuHelp under **System
Settings → Privacy & Security → Accessibility**. Without this permission,
keyboard cleaning and automatic pasting are unavailable; other features remain
usable.

Transcription requests **Speech Recognition** and **Screen & System Audio
Recording** only when starting capture. Permission explanations are localized in
English and Brazilian Portuguese. There is no microphone permission request.
Signature or path changes may require renewed transcription grants as well.

## Transcription architecture

`SystemAudioCapture` uses ScreenCaptureKit and delivers only system audio buffers.
`SpeechTranscriptionBackend` selects a local speech engine.
On supported Macs and languages with macOS 26 or later, `SpeechAnalyzer` and
`SpeechTranscriber` run continuously and publish confirmed passages without
language rewriting options. `AssetInventory` may install local speech assets
before capture. That download can use the network; audio and text remain on the
device.

The fallback uses `SFSpeechRecognizer` with on-device recognition required, a
neutral task hint, and automatic punctuation disabled. It finalizes short
passages at pauses or periodically while retaining audio received during renewal.
Confirmed passages are added to the window and TXT. Partial hypotheses are
recovered only if finalization fails or exceeds its deadline.

`TranscriptionFileStore` writes UTF-8 snapshots atomically. Each session has its
own file; a save error keeps recognized text available for recovery.

## Automated checks

```sh
bash Scripts/test-transcription-storage.sh
bash Scripts/test-transcription-engine.sh
```

The storage test checks UTF-8, separate sessions, atomic writes, and destination
failures. The engine test uses synthetic CoreMedia buffers and a fake speech
backend to check task renewal, finalization, silence, failures, and memory limits.
These tests do not capture real audio or request permissions. Real recognition,
the continuous system backend, and hardware behavior require manual validation.

## Manual validation

- Clicking anywhere on the menu bar icon opens the dashboard.
- System monitoring shows CPU, RAM, and disk usage and stops when disabled.
- Clipboard capture pauses and resumes; text and images survive app restarts.
- Confidential/transient clipboard items are skipped, and clearing removes stored entries and images.
- Shift + Command + V opens history; search, arrow navigation, confirmation, and paste work.
- Keyboard cleaning ends automatically after 30 seconds.
- Prevent Sleep toggles without leaving active power assertions after disabling.
- Brightness offers control only for responding DDC/CI external displays.
- Language switching applies after restart; launch at login and preferences persist.
- Transcription opens from the dashboard and contextual menu without requesting permissions until Start.
- Permission denial explains how to enable access.
- Locally supported English and Portuguese transcribe app/browser playback without microphone input.
- On supported macOS 26 configurations, speech asset preparation precedes capture.
- TXT output retains accents and updates in Documents/MenuHelp/Transcriptions during capture.
- Confirmed passages append without rewriting earlier history.
- Playback longer than two minutes retains full history with both speech backends.
- Stopping immediately after a phrase and quitting preserve final available recognition.
- Closing/reopening the window retains the active session; starting another session creates another file.
- Silence, capture interruption, and unavailable local languages preserve earlier transcripts.
- Show in Finder and Save a Copy work; storage failures leave selectable text available.

## Release configuration

Release enables Hardened Runtime and disables App Sandbox because the app needs
a global event tap and launches bundled DDC/CI helpers. The Xcode **Bundle DDC
tools** phase builds vendored sources without network access. User script
sandboxing is disabled for the target to allow helper and module compilation.

Run `bash Scripts/package-release.sh <version>` to package a universal build.
The script defaults to ad-hoc signing. See [RELEASING.md](RELEASING.md) for
Developer ID signing, optional notarization, and publication. Never commit
certificates, passwords, profiles, transcripts, or generated packages.
