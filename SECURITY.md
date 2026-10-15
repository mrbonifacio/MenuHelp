# Security policy

## Supported versions

During early development, security fixes target the latest source on `main` and
the latest published release. Older releases are not maintained separately.

## Report a vulnerability

Do not post sensitive details in a public issue. Use the repository's
**Security → Report a vulnerability** action to submit a private report:

[Report a vulnerability](https://github.com/mrbonifacio/MenuHelp/security/advisories/new)

Where possible, include:

- macOS version and Mac architecture;
- MenuHelp version or commit;
- minimal reproduction steps;
- observed impact;
- a proof of concept without real personal data.

Reports will be acknowledged as soon as possible. Keep details and fixes private
until a corrected version is available. If the private reporting action is
unavailable, open an issue requesting a private reporting channel without
including vulnerability details or personal data.

## Priority areas

Clipboard history, Accessibility permissions, system audio capture, transcript
storage, execution of bundled brightness helpers, unexpected filesystem writes,
and accidental credential exposure are priority areas for security reports.
