#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
test_work="$(mktemp -d "${TMPDIR:-/tmp}/MenuHelpTranscriptionTest.XXXXXX")"
trap 'rm -rf "$test_work"' EXIT
xcrun swiftc -swift-version 5 \
    -module-cache-path "$test_work/modules" \
    "$task_root/MenuHelp/Transcription/TranscriptionFileStore.swift" \
    "$task_root/Scripts/tests/TranscriptionFileStoreTests.swift" \
    -o "$test_work/test-storage"
"$test_work/test-storage"
