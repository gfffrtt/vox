#!/bin/bash
# Builds Vox.app and packages it as build/Vox.dmg (drag-to-Applications installer).
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/Vox.app/Contents/Info.plist)
DMG="build/Vox-$VERSION.dmg"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

cp -R build/Vox.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "Vox" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "Built $DMG"
