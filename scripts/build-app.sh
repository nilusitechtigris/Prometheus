#!/usr/bin/env bash
# Builds the app into ./build — no Xcode project required.
#
#   scripts/build-app.sh               "Prometheus.app", the public app: one harness, the amber flame icon
#   EDITION=lab scripts/build-app.sh   "Prometheus Lab.app", the private app: every harness version to use
#                                      and test, the pink flame icon. Made from the private code only.
#
# The two have different names, icons and identifiers, so both can be installed on one Mac. They share
# chats and test results, which live in Application Support and don't depend on the identifier.
set -euo pipefail
cd "$(dirname "$0")/.."

EDITION="${EDITION:-standard}"
EXECUTABLE="LocalAIAgent"
case "$EDITION" in
    standard)
        APP_NAME="Prometheus"
        # Kept from the original "Local AI Agent" name so existing settings carry over.
        BUNDLE_ID="com.localaiagent.app"
        ICON_SOURCE="assets/art/originals/flame-ember.png"
        # Where the flame is in that picture (its middle from the top and its height, as shares of the
        # height), then the theme's ground and accent for the tile behind it.
        ICON_FLAME="0.363 0.679 0B0F17 F5A25A"
        ;;
    lab)
        APP_NAME="Prometheus Lab"
        BUNDLE_ID="com.localaiagent.app.lab"
        ICON_SOURCE="assets/art/originals/flame-rose.png"
        ICON_FLAME="0.399 0.590 180C16 FF8FBE"
        ;;
    *)
        echo "EDITION must be standard or lab, not \"$EDITION\"" >&2
        exit 1
        ;;
esac
# "beta" until the 2.0.0 release is tagged: main is built by Update on other people's Macs before then.
VERSION="2.0.0-beta"
APP="build/${APP_NAME}.app"
# Lets an update tell whether it's moving forward. See scripts/update-app.sh.
COMMIT="$(git rev-parse HEAD 2>/dev/null || true)"

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

# One icon for each edition, made again only when its picture or the script changes.
ICNS="build/AppIcon-${EDITION}.icns"
if [[ ! -f "$ICNS" || scripts/make-icon.swift -nt "$ICNS" || "$ICON_SOURCE" -nt "$ICNS" || scripts/build-app.sh -nt "$ICNS" ]]; then
    echo "→ Rendering icon"
    TMP="$(mktemp -d)"
    unset SDKROOT
    # shellcheck disable=SC2086
    swift scripts/make-icon.swift "$ICON_SOURCE" "$TMP/icon.png" $ICON_FLAME >/dev/null
    ICONSET="$TMP/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$ICNS"
    rm -rf "$TMP"
fi
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$APP/Contents/Resources/Fonts"
cp assets/fonts/*.ttf assets/fonts/OFL.txt "$APP/Contents/Resources/Fonts/"
mkdir -p "$APP/Contents/Resources/Art"
# Only the pictures the app shows: the two glass flames. The earlier look's pictures stay in the repo.
cp assets/art/flame-ember.png assets/art/flame-rose.png "$APP/Contents/Resources/Art/"
cp scripts/update-app.sh "$APP/Contents/Resources/"
# The public questions the Harness Test can ask, with the notice their licences need.
mkdir -p "$APP/Contents/Resources/Benchmarks"
cp benchmarks/heldout/heldout-v1.jsonl benchmarks/heldout/practice-v1.jsonl benchmarks/heldout/NOTICE.md "$APP/Contents/Resources/Benchmarks/"

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
    <key>PrometheusCommit</key><string>${COMMIT}</string>
    <key>PrometheusEdition</key><string>${EDITION}</string>
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
