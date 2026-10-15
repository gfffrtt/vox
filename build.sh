#!/bin/bash
# Builds Vox.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Vox.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Pick the newest SDK whose Swift interface was built by a compiler no newer than ours
# (Command Line Tools can ship SDKs ahead of the installed compiler).
if [ -z "${SDKROOT:-}" ]; then
    COMPILER=$(swiftc --version 2>&1 | sed -nE 's/.*Apple Swift version ([0-9]+\.[0-9]+).*/\1/p' | head -1)
    for sdk in $(ls -d "$(xcode-select -p)"/SDKs/MacOSX[0-9]*.sdk | sort -rV); do
        iface=$(ls "$sdk"/usr/lib/swift/Swift.swiftmodule/*.swiftinterface 2>/dev/null | head -1)
        built=$(sed -nE 's/.*swift-compiler-version: Apple Swift version ([0-9]+\.[0-9]+).*/\1/p' "$iface" | head -1)
        if [ -n "$built" ] && [ "$(printf '%s\n%s\n' "$built" "$COMPILER" | sort -V | tail -1)" = "$COMPILER" ]; then
            export SDKROOT="$sdk"
            break
        fi
    done
fi
echo "Using SDK: ${SDKROOT:-default}"

# Compiled with swiftc directly (works even when SwiftPM in Command Line Tools is broken).
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
    -o "$APP/Contents/MacOS/Vox" Sources/Vox/*.swift

# App icon (regenerate with: swift scripts/make-icon.swift Resources/AppIcon.icns).
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Vox</string>
    <key>CFBundleDisplayName</key><string>Vox</string>
    <key>CFBundleIdentifier</key><string>local.vox.Vox</string>
    <key>CFBundleExecutable</key><string>Vox</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Vox records your voice while you hold the dictation shortcut.</string>
</dict>
</plist>
EOF

# Sign with a stable self-signed identity kept in its own keychain. macOS ties Accessibility
# grants and keychain access to the code signature; an ad-hoc signature changes on every build,
# which silently revokes Accessibility and makes the keychain prompt for a password again.
IDENTITY="Vox Local Signing"
KEYCHAIN="$HOME/Library/Keychains/vox-signing.keychain-db"
KEYCHAIN_PASS="vox-signing"
if [ ! -f "$KEYCHAIN" ]; then
    echo "Creating local signing identity \"$IDENTITY\""
    TMP=$(mktemp -d)
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$IDENTITY" \
        -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
        -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" \
        -addext "basicConstraints=critical,CA:false" 2>/dev/null
    openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:vox
    security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
    security set-keychain-settings "$KEYCHAIN"   # no auto-lock
    security import "$TMP/id.p12" -k "$KEYCHAIN" -P vox -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null
    rm -rf "$TMP"
fi
# codesign only finds identities in keychains on the user search list.
if ! security list-keychains -d user | grep -q "vox-signing.keychain-db"; then
    eval "security list-keychains -d user -s $(security list-keychains -d user | tr '\n' ' ') \"$KEYCHAIN\""
fi
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
codesign --force --keychain "$KEYCHAIN" --sign "$IDENTITY" --identifier local.vox.Vox "$APP"

echo "Built $APP"
