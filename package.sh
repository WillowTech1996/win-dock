#!/bin/bash
# Build a Release app and zip it with ditto, which preserves the signed bundle.
# Verifies the signature of the zip's contents before declaring success.
set -e
cd "$(dirname "$0")"

./build.sh

APP=build/Build/Products/Release/WinDock.app
ZIP=build/WinDock.zip
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

CHECK=$(mktemp -d)
ditto -x -k "$ZIP" "$CHECK"
codesign --verify --deep --strict "$CHECK/WinDock.app"
echo "zip signature OK: $ZIP"
codesign -dvv "$CHECK/WinDock.app" 2>&1 | grep -E 'Authority|TeamIdentifier' | head -3
spctl -a -vv "$CHECK/WinDock.app" 2>&1 | head -2 || true
echo "note: not notarized, so other Macs will block it in Gatekeeper"
rm -rf "$CHECK"
