#!/bin/bash
# Builds Vox.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Vox.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

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

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Vox</string>
    <key>CFBundleDisplayName</key><string>Vox</string>
    <key>CFBundleIdentifier</key><string>local.vox.Vox</string>
    <key>CFBundleExecutable</key><string>Vox</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Vox records your voice while you hold the dictation shortcut.</string>
</dict>
</plist>
EOF

# Ad-hoc signature. macOS ties Accessibility/Microphone grants to the signature,
# so after a rebuild you may need to re-enable Vox in Privacy & Security.
codesign --force --sign - "$APP"

echo "Built $APP"
