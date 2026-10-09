#!/usr/bin/env bash
# Ad-hoc sign the app and strip the quarantine bit for local runs.
# Distribution requires Developer ID + notarization (see docs/ROADMAP.md, M5).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-dist/OneClick.app}"

codesign --force --deep --sign - \
    --entitlements Resources/oneclick.entitlements \
    "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
codesign --verify --verbose "$APP"
echo "==> Ad-hoc signed: $APP"
