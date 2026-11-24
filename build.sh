#!/bin/bash
# Release build into ./build. Output is prettified if `xcpretty` is installed (gem install xcpretty).
# Do not modify the .app after this step: any change inside the bundle breaks the code signature.
set -e
set -o pipefail

rm -rf build/Build/Products/Release || true

PRETTY=cat
command -v xcpretty >/dev/null && PRETTY=xcpretty
xcodebuild -scheme WinDock -configuration Release -derivedDataPath build -quiet -allowProvisioningUpdates | $PRETTY

APP=build/Build/Products/Release/WinDock.app
codesign --verify --deep --strict "$APP"
echo "build finished successfully (signature verified)"
echo "to open the app, run: open $APP"
