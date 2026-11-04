#!/usr/bin/env bash
# Builds "Prometheus.app" into ./build — no Xcode project required.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Prometheus"
EXECUTABLE="LocalAIAgent"
# Kept from the original "Local AI Agent" name so existing settings carry over.
BUNDLE_ID="com.localaiagent.app"
VERSION="1.0.0"
APP="build/${APP_NAME}.app"

# Command Line Tools ship newer SDKs whose SwiftUI `@State` macro plugin is only bundled with Xcode.
# In that case, fall back to the newest installed SDK that doesn't need it.
choose_sdk() {
    local dev
    dev="$(xcode-select -p 2>/dev/null || true)"
    [[ "$dev" == *CommandLineTools* ]] || return 0
    [[ -e "$dev/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]] && return 0
    local sdk
    for sdk in $(ls -d "$dev"/SDKs/MacOSX[0-9]*.sdk 2>/dev/null | sort -t X -k 2 -V -r); do
        if ! grep -qs 'type: "StateMacro"' \
            "$sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface" \
            "$sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface"; then
            echo "$sdk"
            return 0
        fi
    done
}

SDK="$(choose_sdk)"
if [[ -n "$SDK" ]]; then
    echo "→ Using SDK: $(basename "$SDK")"
    export SDKROOT="$SDK"
fi

echo "→ Compiling (release)…"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

echo "→ Assembling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"

if [[ ! -f build/AppIcon.icns || scripts/make-icon.swift -nt build/AppIcon.icns || assets/icon-source.png -nt build/AppIcon.icns ]]; then
    echo "→ Rendering icon"
    TMP="$(mktemp -d)"
    unset SDKROOT
    swift scripts/make-icon.swift assets/icon-source.png "$TMP/icon.png" >/dev/null
    ICONSET="$TMP/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o build/AppIcon.icns
    rm -rf "$TMP"
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$APP/Contents/Resources/Fonts"
cp assets/fonts/*.ttf assets/fonts/OFL.txt "$APP/Contents/Resources/Fonts/"
mkdir -p "$APP/Contents/Resources/Art"
cp assets/art/*.png "$APP/Contents/Resources/Art/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${EXECUTABLE}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key><true/>
    </dict>
</dict>
</plist>
PLIST

echo "→ Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP" >/dev/null

echo "✓ Built: $APP"
