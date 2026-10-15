# Contributing to MenuHelp

Thank you for helping improve MenuHelp.

## Get started

1. Fork the repository and create a short-lived branch for your change.
2. Follow [SETUP.md](SETUP.md) using Xcode 26 or later.
3. Build locally without committing user settings, certificates, or a Team ID.
4. Keep each pull request focused on one problem and describe the resulting behavior.

## Before submitting

Run the unsigned Debug build described in SETUP.md. For transcription changes,
also run:

```sh
bash Scripts/test-transcription-storage.sh
bash Scripts/test-transcription-engine.sh
```

Complete the manual checks relevant to your change. Confirm that:

- No tokens, certificates, clipboard contents, transcripts, or personal paths are included.
- New permissions have a clear explanation visible to the user.
- Clipboard changes respect confidential and transient content markers.
- External processes receive separate arguments instead of constructed shell commands.
- README, the user guide, and PRIVACY.md describe the actual behavior.
- New user-facing strings are localized in English and Brazilian Portuguese.
- Project documentation and pull request descriptions are written in English.

Include relevant build/test results and any hardware or permission checks you
could not perform. Preserve third-party source and license notices.

Report vulnerabilities privately according to [SECURITY.md](SECURITY.md), rather
than opening a public issue with sensitive details.
