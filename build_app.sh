#!/bin/bash
# Builds Snip.app into build/ from the SwiftPM release binary.
set -euo pipefail
cd "$(dirname "$0")"

APP=Snip

swift build -c release

rm -rf "build/$APP.app"
mkdir -p "build/$APP.app/Contents/MacOS" "build/$APP.app/Contents/Resources"
cp ".build/release/$APP" "build/$APP.app/Contents/MacOS/$APP"
cp Resources/Info.plist "build/$APP.app/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "build/$APP.app/Contents/Resources/AppIcon.icns"
fi

# Absolute path on purpose: a Homebrew or conda "codesign" earlier on PATH is a
# different tool and chokes on the bundle.
/usr/bin/codesign --force -s - "build/$APP.app"
echo "Built build/$APP.app"
