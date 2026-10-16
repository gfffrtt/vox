#!/bin/bash
# Builds a Developer ID-signed Vox.app and packages it as a notarized build/Vox-<version>.dmg
# (drag-to-Applications installer). Each run releases the next version from ./VERSION:
#   ./make-dmg.sh         1.0 → 1.1
#   ./make-dmg.sh 2.0     release as 2.0
# The build number always goes up by one. ./VERSION is only updated once notarization succeeds,
# so a failed run can simply be retried. Notarization uses credentials saved once with:
#   xcrun notarytool store-credentials vox-notary --apple-id <email> --team-id <team id>
set -euo pipefail
cd "$(dirname "$0")"

NOTARY_PROFILE="${NOTARY_PROFILE:-vox-notary}"

source VERSION
if [ -n "${1:-}" ]; then
    VERSION="$1"
else
    VERSION="${VERSION%.*}.$(( ${VERSION##*.} + 1 ))"   # bump the last component
fi
BUILD=$((BUILD + 1))
echo "Releasing Vox $VERSION (build $BUILD)"

VOX_VERSION="$VERSION" VOX_BUILD="$BUILD" ./build.sh --release
IDENTITY=$(codesign -dvv build/Vox.app 2>&1 | sed -nE 's/^Authority=(Developer ID Application: .*)/\1/p')

DMG="build/Vox-$VERSION.dmg"
RW_DMG="build/Vox-rw.dmg"
VOLNAME="Vox"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING" "$RW_DMG"' EXIT

if [ -d "/Volumes/$VOLNAME" ]; then
    echo "A volume named \"$VOLNAME\" is already mounted; eject it first." >&2
    exit 1
fi

cp -R build/Vox.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
# Window background (regenerate with: swift scripts/make-dmg-background.swift Resources/DMGBackground.tiff).
mkdir "$STAGING/.background"
cp Resources/DMGBackground.tiff "$STAGING/.background/background.tiff"

# Lay out the window on a writable image, then compress it. Finder stores the layout in the
# volume's .DS_Store. Icon positions must match scripts/make-dmg-background.swift.
rm -f "$DMG" "$RW_DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -fs HFS+ -format UDRW -ov "$RW_DMG" >/dev/null
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" | awk '/Apple_HFS/ {print $1}')

osascript <<EOF
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 840, 548}
        set opts to icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 112
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "Vox.app" to {160, 190}
        set position of item "Applications" to {480, 190}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

sync
hdiutil detach "$DEVICE" >/dev/null
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null

# Notarizing the DMG covers the app inside it; stapling attaches the ticket so Gatekeeper
# can verify it offline.
codesign --timestamp --sign "$IDENTITY" "$DMG"
echo "Notarizing $DMG (usually takes a few minutes)..."
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -vv "$DMG"

printf 'VERSION=%s\nBUILD=%s\n' "$VERSION" "$BUILD" > VERSION
echo "Built $DMG"
