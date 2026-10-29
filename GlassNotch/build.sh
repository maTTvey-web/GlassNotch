#!/bin/bash
# Builds build/GlassNotch.app with the Swift toolchain (Xcode or Command Line Tools). Run: bash build.sh
set -e
APP="build/GlassNotch.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS"
swiftc -O -parse-as-library -target "$(uname -m)-apple-macos14.0" Sources/*.swift -o "$APP/Contents/MacOS/GlassNotch"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
echo "Done: $APP  (run: open $APP)"
