# Bundled DDC tools

These are separate command-line programs launched by MenuHelp using their
standard CLI. They are compiled from the vendored sources, without downloads
or Homebrew, by `Scripts/build-ddc.sh`. No upstream source modifications.

| Tool | Upstream | Pinned commit | License | Architecture |
| --- | --- | --- | --- | --- |
| m1ddc | https://github.com/waydabber/m1ddc | `04d949794102eb8df01ad3681afff6464a3eede2` | MIT | arm64 |
| ddcctl | https://github.com/kfix/ddcctl | `06c7ab6eba5b1c903678f8113a92cef990acaf90` | GPL-3.0 | x86_64 |

Each directory includes the original sources, headers, Makefile, README and
license. Preserve these notices in redistributions. The main MenuHelp sources
retain their MIT license; ddcctl is distributed as a separate GPL program,
not linked into the MenuHelp executable.

Every app bundle includes `Contents/Resources/ThirdPartySources.zip` with these
sources and the build script, plus the licenses in `Contents/Resources/Licenses`.
The same sources are available in the release's source archive. To rebuild the
bundled tools, extract that ZIP and run:

```sh
bash Scripts/build-ddc.sh ./rebuilt
```

This requires Xcode on a Mac, not Homebrew. Build both architectures on either
Intel or Apple Silicon; run each helper only on its supported hardware. The
resulting `rebuilt/Helpers` directory contains the two executables. Users may
modify/rebuild the helpers and app; no vendor-specific signing key is required
for a local ad-hoc build (`bash Scripts/package-release.sh`).
