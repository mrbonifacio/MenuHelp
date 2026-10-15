# Privacy policy

MenuHelp operates locally. It has no accounts, analytics, telemetry, advertising,
or content uploads to servers.

## Clipboard history

When enabled, MenuHelp observes the general macOS clipboard and stores text and
images under:

```text
~/Library/Application Support/MenuHelp/
```

Defaults are **100 items** retained for **30 days**. Settings offers maximums of
50, 100, 250, or 500 items and retention of 7, 30, or 90 days, or no expiration.
Images have a fixed combined 200 MB limit. History can be paused or cleared at
any time.

Content marked by compatible apps as confidential, transient, or automatically
generated is skipped. This protection depends on the source app publishing the
correct markers and does not cover all sensitive content.

Data is stored as JSON and PNG without application-level encryption. The storage
directory uses `0700` permissions and files use `0600`, restricting normal access
to the current user. FileVault provides separate protection for the disk at rest.

## Accessibility and keyboard input

Accessibility permission is used to block keyboard events during cleaning mode
and simulate **Command + V** after a clipboard history selection. The global
**Shift + Command + V** shortcut is registered through Carbon. MenuHelp does not
record, transmit, or keep a log of typed keys.

## System audio transcription

This feature is in the current source and is not included in the published 0.2.0
package. Capture starts only after clicking **Start Transcription**. MenuHelp uses
ScreenCaptureKit to receive system playback and requests macOS **Screen & System
Audio Recording** permission. Only audio buffers are delivered to the app; screen
images are not processed or saved. Microphone input and MenuHelp's own audio are
excluded.

Speech recognition requires its own permission and runs on the device. On
supported Macs and languages with macOS 26 or later, the app uses the continuous
system speech backend. macOS may download local speech assets before capture;
audio and recognized text are not uploaded as part of that download. Other
supported configurations use the earlier on-device recognition backend. Languages
without local recognition are rejected; the app does not use a server fallback.
Audio buffers are kept temporarily in memory and discarded. No audio or video
recording file is created.

Confirmed passages are added to the session history and automatically saved as
UTF-8 text under:

```text
~/Documents/MenuHelp/Transcriptions/
```

Temporary hypotheses do not replace confirmed passages. If finalization fails or
times out, the app attempts to preserve the latest available hypothesis as well.
The TXT includes the start time, passage intervals relative to session start,
and duration; ending the session adds the end date and time.

Each session has a separate TXT file with `0600` permissions; the directory is
created with `0700`. These files do not expire automatically. Remove them in
Finder. **Save a Copy…** creates an additional file at your chosen destination.
If Documents or an export destination syncs through iCloud or another service,
that service controls synchronization independently of MenuHelp.

Closing the window keeps capture active. **Stop and Save** ends capture,
finalizes recognition, and saves the transcript. Quitting performs the same
finalization; an unresolved save failure keeps the app open so the text can be
preserved. Capture includes notifications and other audible conversations or
app sounds. Protected audio may be unavailable.

## Brightness control

MenuHelp runs the bundled `m1ddc` (Apple Silicon) or `ddcctl` (Intel) executable
from `MenuHelp.app/Contents/Helpers`. It does not download additional tools or
search PATH or Homebrew installations. These helpers query local displays and
send DDC/CI brightness commands. Sources and licenses ship with the app and are
available in this repository.

## Preferences and data removal

Preferences are stored through macOS UserDefaults. Use **Settings → Clipboard
History → Clear…** or the history window to remove saved clipboard entries.
After quitting, you may also remove the Application Support directory above and
the preferences domain matching the app's bundle identifier to reset local data
and settings. Check launch-at-login registration separately in macOS settings.

Delete transcripts and exported copies separately from their folders. Clearing
clipboard history does not remove TXT files. Deleting local files does not
necessarily remove copies retained by backup or synchronization services.
