#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
test_work="$(mktemp -d "${TMPDIR:-/tmp}/MenuHelpSpeechTest.XXXXXX")"
trap 'rm -rf "$test_work"' EXIT

# Substitute only Apple's Speech types; execute the actual engine with synthetic
# CoreMedia audio. These tests never request permissions or capture real audio.
python3 - "$task_root" "$test_work" <<'PY'
from pathlib import Path
import sys
root, output = map(Path, sys.argv[1:])
harness = (root / 'Scripts/tests/SpeechTranscriptionEngineTests.swift').read_text()
transcription = (root / 'MenuHelp/Transcription/TimedTranscription.swift').read_text()
engine = (root / 'MenuHelp/Transcription/SpeechTranscriptionEngine.swift').read_text()
engine = engine.replace('@preconcurrency import Speech\n', '')
(output / 'EngineTests.swift').write_text(harness + '\n' + transcription + '\n' + engine)
PY
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor \
    -strict-concurrency=complete -warnings-as-errors \
    -module-cache-path "$test_work/modules" \
    "$test_work/EngineTests.swift" -o "$test_work/test-engine"
"$test_work/test-engine"
