#!/bin/bash
# Compile mPIE.app (release), avec son icône, ses langues et la signature stable, puis l'installe dans
# ~/Applications/Applications Personnelles.
# Usage : ./build_app.sh   (NO_INSTALL=1 : ne pas installer)
#   DEV=1 : édition de développement « mPIE DEV.app » (bundle id …dev, données à part), dans le dossier du projet, non installée.
set -euo pipefail
cd "$(dirname "$0")"

TOOLS=/Volumes/SKYRIM/TOOLS
DEST="${MPIE_INSTALL_DIR:-$HOME/Applications/Applications Personnelles}"
# Sans VERSION, la version de la dernière publication (étiquette git vX.Y.Z) : une copie locale numérotée 1.0.0 serait
# remplacée par la mise à jour automatique, même par une publication plus ancienne que son code (incident du 14/11/2026).
VERSION="${VERSION:-$(git tag --list 'v[0-9]*' --sort=-v:refname 2>/dev/null | head -1 | sed 's/^v//')}"
VERSION="${VERSION:-1.0.0}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
if [ -n "${DEV:-}" ]; then
    APP="mPIE DEV.app"; BUNDLE_ID=fr.stephan.mpie.dev; NAME="mPIE DEV"; NO_INSTALL=1
else
    APP=mPIE.app; BUNDLE_ID=fr.stephan.mpie; NAME=mPIE
fi

# Socle et mises à jour : copies reprises à chaque build (ne pas les modifier ici).
[ -f "$TOOLS/DESIGN/Socle/swift/Socle.swift" ] && cp "$TOOLS/DESIGN/Socle/swift/Socle.swift" Sources/mPIE/Socle.swift
for f in Updater.swift UpdaterView.swift; do
    [ -f "$TOOLS/MAC/_TOOLS/shared/$f" ] && cp "$TOOLS/MAC/_TOOLS/shared/$f" "Sources/mPIE/$f"
done

if [ ! -f assets/mPIE.icns ]; then
    mkdir -p assets
    TMP="$(mktemp -d)"
    swift scripts/make_icon.swift "$TMP/icon.png"
    mkdir "$TMP/mPIE.iconset"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$TMP/icon.png" --out "$TMP/mPIE.iconset/icon_${s}x${s}.png" >/dev/null
        sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$TMP/mPIE.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$TMP/mPIE.iconset" -o assets/mPIE.icns
    cp "$TMP/icon.png" assets/mPIE.png
    rm -rf "$TMP"
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/mPIE"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/mPIE"
cp assets/mPIE.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
EXTRA=""
[ -n "${DEV:-}" ] && EXTRA='<key>SkyrimUpdateAcceptBundleID</key><string>fr.stephan.mpie</string><key>LSEnvironment</key><dict><key>MPIE_DATA_DIR</key><string>~/Library/Application Support/mPIE-dev</string></dict>'
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>mPIE</string>
    <key>CFBundleIconFile</key><string>mPIE</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>fr</string><string>en</string><string>es</string><string>it</string></array>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>mPIE pilote Musique ou Spotify depuis le menu circulaire.</string>
    $EXTRA
    <key>NSHumanReadableCopyright</key><string>© 2026 Starbudweiser</string>
</dict>
</plist>
PLIST

if [ -x "$TOOLS/MAC/_tools/sign_app.sh" ]; then
    "$TOOLS/MAC/_tools/sign_app.sh" "$APP"
else
    codesign --force --deep --sign - "$APP"   # signature ad hoc hors de ma machine
fi

if [ "${NO_INSTALL:-0}" != 1 ]; then
    mkdir -p "$DEST"
    osascript -e "if application id \"$BUNDLE_ID\" is running then tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
    rm -rf "$DEST/$APP"
    cp -R "$APP" "$DEST/"
    echo "Installé : $DEST/$APP"
fi
