#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 1 ]]; then
    echo 'Usage: script/test_editor_window_state.sh "/path/to/a/saved/local/test/project"' >&2
    exit 2
fi
harness="$(mktemp -d)"
trap 'rm -rf "$harness"' EXIT
xcrun swiftc -module-cache-path "$harness/modules" \
    Shared/VidiStudioShareLink.swift tests/editor_window_state_harness.swift \
    -o "$harness/editor-window-test"
"$harness/editor-window-test" "$1"
