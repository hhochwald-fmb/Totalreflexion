#!/bin/sh
# Baut Totalreflexion zur Weitergabe außerhalb des App Stores: signiert mit "Developer ID Application",
# lässt App und DMG von Apple notarisieren und legt die fertige DMG nach build/release/.
#
# Einmalig vorher:
#   1. Xcode › Einstellungen › Accounts › Team auswählen › "Manage Certificates…" › + › "Developer ID Application"
#   2. Zugangsdaten für die Notarisierung im Schlüsselbund ablegen:
#        xcrun notarytool store-credentials "Totalreflexion" --apple-id <deine Apple-ID> --team-id 92TY4G7V4Z
#      (fragt nach einem app-spezifischen Passwort, erstellt unter https://account.apple.com › Anmeldung und Sicherheit)
#
# Zum Testen ohne Zertifikat: SIGN_IDENTITY=- SKIP_NOTARIZE=1 ./scripts/release.sh
set -eu

TEAM_ID="${TEAM_ID:-92TY4G7V4Z}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-Totalreflexion}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/release"
ARCHIVE="$OUT/Totalreflexion.xcarchive"

notarize() {
    if [ "$SKIP_NOTARIZE" = "1" ]; then
        echo "Notarisierung übersprungen: $1"
        return
    fi
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

rm -rf "$OUT"
mkdir -p "$OUT"

if command -v xcodegen >/dev/null 2>&1; then
    (cd "$ROOT" && xcodegen generate --quiet)
fi

echo "==> Archivieren (Release)"
xcodebuild -project "$ROOT/Totalreflexion.xcodeproj" -scheme Totalreflexion -configuration Release \
    -destination "generic/platform=macOS" -archivePath "$ARCHIVE" -quiet archive \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    OTHER_CODE_SIGN_FLAGS="--timestamp"

APP="$OUT/Totalreflexion.app"
ditto "$ARCHIVE/Products/Applications/Totalreflexion.app" "$APP"
codesign --verify --deep --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")"

echo "==> App notarisieren"
ditto -c -k --keepParent "$APP" "$OUT/Totalreflexion.zip"
notarize "$OUT/Totalreflexion.zip"
[ "$SKIP_NOTARIZE" = "1" ] || xcrun stapler staple "$APP"
rm "$OUT/Totalreflexion.zip"

echo "==> DMG erstellen"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Totalreflexion.app"
ln -s /Applications "$STAGE/Programme"
# Die GPL-3 verlangt, dass der Lizenztext der App beiliegt.
cp "$ROOT/LICENSE.md" "$STAGE/Lizenz (GPL-3).md"
DMG="$OUT/Totalreflexion-$VERSION.dmg"
hdiutil create -quiet -volname "Totalreflexion $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
rm -rf "$STAGE"

echo "==> DMG notarisieren"
notarize "$DMG"
if [ "$SKIP_NOTARIZE" != "1" ]; then
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

echo "Fertig: $DMG"
