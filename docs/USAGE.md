# User guide

This guide describes the current source. Audio transcription is not included in
the published 0.2.0 package; build the current source to use it.

## Open the dashboard and settings

MenuHelp runs in the menu bar without a Dock icon. Click its menu bar icon to
open the dashboard. Right-click the icon to open Settings, Audio Transcription,
or Quit. The dashboard provides feature switches and external display controls.

## System monitoring

Enable **System Monitoring** in the dashboard. CPU, memory, and disk meters
refresh approximately every two seconds. CPU measures overall activity, memory
estimates used physical memory excluding reclaimable cache, and disk shows usage
of the startup volume. Disable the switch to stop sampling. The setting persists
between launches.

## Clipboard history

1. Enable **Clipboard History** in the dashboard or **Record new items** in Settings.
2. Copy text or an image in another app.
3. Press **Shift + Command + V**, or click **Open History** in the dashboard.
4. Use the search field to filter history. Navigate with **↑ / ↓** and press
   **Enter** to confirm a selection and paste into the previous app.
5. Use **Copy Again** on an item to put it back on the clipboard.

Automatic pasting requires Accessibility permission. Allow MenuHelp in **System
Settings → Privacy & Security → Accessibility**. If access is unavailable, use
Copy Again and paste manually in the destination app.

In **Settings → Clipboard History**, choose a maximum of **50, 100, 250, or 500**
items and automatic deletion after **7, 30, or 90 days**, or **Never**. Defaults
are **100 items** and **30 days**. Images have a fixed combined **200 MB** limit.
Pausing history stops new captures while keeping saved entries. Use **Clear…**
in Settings or the history window to delete saved text and images.

In **Settings → Shortcuts**, enable or disable all shortcuts or just the history
shortcut. The key combination is fixed. If another app has registered it,
disable the conflicting shortcut in that app and try again.

History survives app restarts. Compatible apps can mark clipboard content as
confidential or transient so that MenuHelp skips it. This depends on the source
app; review the [privacy policy](../PRIVACY.md) before copying sensitive content.

## Keyboard cleaning

Enable **Keyboard Cleaning** in the dashboard, granting Accessibility access if
requested. Keyboard input is blocked for **30 seconds**, and the dashboard shows
the remaining time. The mode ends automatically. It is temporary and must be
started again for another cleaning session.

## Prevent Sleep

Enable **Prevent Sleep** to prevent automatic idle sleep of the system and
display. Disable it to restore normal idle behavior. The preference persists
across launches. This feature does not promise to override lid closure, manual
sleep, shutdown, or other system power policies.

## External display brightness

Connect an external monitor that supports **DDC/CI** and enable DDC/CI in the
monitor's own menu. Open the dashboard and adjust its brightness slider. Use
**Check monitors again** after changing connections.

The app bundles `m1ddc` for Apple Silicon and `ddcctl` for Intel. It runs only the
helpers inside its own bundle. No separate installation is needed. Built-in
MacBook displays are not controlled by these helpers. Docks, adapters, ports,
and cables can prevent DDC/CI communication even when the monitor supports it.

If a display is detected but cannot be controlled, enable DDC/CI and try another
cable or a direct connection. If a bundled helper is missing, reinstall the app.

## System audio transcription

1. Open **Audio Transcription** from the dashboard or the icon's right-click menu.
2. Choose the spoken **Audio language** and click **Start Transcription**.
3. Grant **Speech Recognition** and **Screen & System Audio Recording** when
   macOS requests them. Reopen the app if required after changing permissions.
4. Wait for local speech preparation to finish, then play the audio in a browser
   or another app. The audio level indicates incoming system playback.
5. Click **Stop and Save**. Use **Show in Finder** to locate the saved file or
   **Save a Copy…** to export it to another folder.

Every session creates a separate UTF-8 TXT file in:

```text
~/Documents/MenuHelp/Transcriptions/
```

The file updates automatically during capture. It contains the start date and
time, timestamped passages such as `[00:00:12 – 00:00:18]`, and session duration.
Stopping adds the end date and time. Confirmed passages remain in the history;
recognition may take a short time to confirm a passage.

Closing the window keeps transcription running. Reopen it to follow the current
session. Quitting MenuHelp finalizes the capture and saves the text. If saving
fails, the app keeps the text available and prevents normal termination until it
can be preserved. Use Save a Copy or copy the selectable text before retrying.

On supported Macs and languages running macOS 26 or later, transcription uses
`SpeechAnalyzer` and `SpeechTranscriber` for a continuous local session. macOS
may need to download the selected language's speech assets before capture starts.
Other supported configurations use local `SFSpeechRecognizer` sessions, finalizing
short passages at pauses or periodically while retaining incoming audio during
renewal. No additional language rewriting is applied.

Both paths require on-device recognition. Languages without local support are
rejected. The language list comes from macOS; listing a language does not guarantee
that a local model is installed. Check **System Settings → Keyboard → Dictation**
for the language, allow any installation to finish, or choose another language.

Capture includes other app sounds, notifications, and remote voices played through
the computer. **The microphone is not captured**, so your own microphone speech
in a call is excluded unless another app plays it back. The app's own audio is
excluded. Protected media may not provide capturable audio. No audio or video
files are saved.

If recognition stops or takes too long to finalize, confirmed text is preserved
and the app attempts to recover the latest partial passage. Start another session
to continue. If a TXT write fails, check free space and folder permissions and
use Save a Copy to preserve the text.

## Language and launch at login

Open **Settings → Language** to select **Automatic (Mac language)**, **English**,
or **Portuguese (Brazil)**. Restart MenuHelp when prompted to apply the change.
The interface language and the transcription audio language are separate settings.

Enable **Launch at Login** under **General** to open MenuHelp when you sign in.
If macOS requires approval, review its Login Items settings. Keep the app in
Applications so its path remains stable.

## Permissions and troubleshooting

Permissions are managed under **System Settings → Privacy & Security**:

| Symptom | What to check |
| --- | --- |
| Keyboard cleaning or automatic paste fails | Enable Accessibility for MenuHelp. |
| Transcription cannot start capture | Enable Screen & System Audio Recording, then reopen the app. |
| Speech recognition is denied | Enable Speech Recognition for MenuHelp. |
| Local recognition is unavailable | Check the selected Dictation language and downloaded speech assets. |
| History shortcut does not open | Enable it in Settings and check for a conflicting app. |
| External brightness is unavailable | Enable DDC/CI and check the physical connection. |
| First launch is blocked | Follow the installation guide's Open Anyway instructions. |

Changing the app's signature or path can invalidate existing permission grants.
Remove and re-add MenuHelp in the relevant settings if necessary.

## Remove stored data

Clear clipboard history from Settings or the history window. Transcript files
have no automatic expiration; delete them and any exported copies in Finder.
Clearing clipboard history does not delete transcripts. See the
[privacy policy](../PRIVACY.md) for storage locations and synchronization details.
