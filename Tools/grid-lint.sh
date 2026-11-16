#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAIL=0

if grep -rn '\.formStyle(\.grouped)' Sources/Vorssaint/UI/; then
    echo "FAIL grid-lint: raw .formStyle(.grouped) found in Sources/Vorssaint/UI/" >&2
    FAIL=1
fi

RAW_TOGGLES="$(grep -rn '\.toggleStyle(\.\(switch\|checkbox\))' Sources/Vorssaint/UI/ | grep -v '///' | grep -v 'SettingsCard\.swift:.*\.toggleStyle(\.switch)' || true)"
if [[ -n "$RAW_TOGGLES" ]]; then
    echo "FAIL grid-lint: raw .toggleStyle(.switch/.checkbox) found in UI:" >&2
    echo "$RAW_TOGGLES" >&2
    FAIL=1
fi

if ! grep -q 'enum DesignSpace' Sources/Vorssaint/UI/DesignSystem/DesignTokens.swift; then
    echo "FAIL grid-lint: missing DesignSpace token scale in DesignTokens.swift" >&2
    FAIL=1
fi

if ! grep -q 'struct VorssaintCompactSwitchStyle' Sources/Vorssaint/UI/DesignSystem/VorssaintDesignKit.swift; then
    echo "FAIL grid-lint: missing VorssaintCompactSwitchStyle in VorssaintDesignKit.swift" >&2
    FAIL=1
fi

python3 Tests/generate_sources.py

if (( FAIL )); then
    exit 1
fi
echo "PASS grid-lint: DesignSpace tokens, DesignKit controls, and generate_sources anchors verified."
