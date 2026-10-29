#!/bin/bash
# Builds GlassNotch.app and packs it into ../GlassNotch.dmg (drag GlassNotch to Applications). Run on a Mac.
set -e
cd "$(dirname "$0")"
bash build.sh
rm -rf dmg && mkdir dmg
cp -R build/GlassNotch.app dmg/
ln -s /Applications dmg/Applications
rm -f ../GlassNotch.dmg
hdiutil create -volname "GlassNotch" -srcfolder dmg -ov -format UDZO ../GlassNotch.dmg
rm -rf dmg
echo "Done: GlassNotch.dmg"
