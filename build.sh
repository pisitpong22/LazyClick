#!/bin/bash
# Builds "LazyClick.app" (arm64, Release) into ./build and runs the unit tests first.
#
#   ./build.sh              build + test + bundle + ad-hoc sign
#   SKIP_TESTS=1 ./build.sh skip the test run
#   CODESIGN_IDENTITY="Apple Development: Name (TEAMID)" ./build.sh
#                           sign with a stable identity so the Accessibility grant survives rebuilds
#   CODESIGN_IDENTITY="Developer ID Application" ./build.sh
#                           release: also notarize + staple and write build/LazyClick.zip and build/LazyClick.dmg
#                           (once first: xcrun notarytool store-credentials LazyClick)
#                           and build/appcast.xml for Sparkle; upload all three to the vVERSION GitHub release
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="LazyClick"
BIN_NAME="LazyClick"
# Local builds take the latest release tag, so they don't report an older version than what's installed.
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 1.0.0)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
IDENTITY="${CODESIGN_IDENTITY:--}"
OUT="build/${APP_NAME}.app"

if [[ "$(uname -m)" != "arm64" ]]; then echo "warning: not an Apple Silicon host; still building arm64" >&2; fi

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
  echo "==> Running unit tests"
  if ! swift test > build.test.log 2>&1; then grep -E "error:" build.test.log | head -20 >&2; echo "Unit tests FAILED (see build.test.log)" >&2; exit 1; fi
  grep -E "Executed [0-9]+ tests" build.test.log | tail -1
fi

echo "==> Building Release (arm64)"
swift build -c release --arch arm64 --product "$BIN_NAME"
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

echo "==> Assembling ${OUT}"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN_DIR/$BIN_NAME" "$OUT/Contents/MacOS/$BIN_NAME"
mkdir -p "$OUT/Contents/Frameworks"
ditto "$BIN_DIR/Sparkle.framework" "$OUT/Contents/Frameworks/Sparkle.framework"
# The XPC services are only for sandboxed apps; LazyClick is not sandboxed.
rm -rf "$OUT/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$OUT/Contents/Frameworks/Sparkle.framework/XPCServices"
install_name_tool -add_rpath @executable_path/../Frameworks "$OUT/Contents/MacOS/$BIN_NAME"
cp "Resources/Magic Mouse.wav" "$OUT/Contents/Resources/"
sed -e "s/__VERSION__/${VERSION}/" -e "s/__BUILD__/${BUILD_NUMBER}/" Resources/Info.plist > "$OUT/Contents/Info.plist"
printf 'APPL????' > "$OUT/Contents/PkgInfo"
strip -x "$OUT/Contents/MacOS/$BIN_NAME" 2>/dev/null || true

if swift scripts/make_icon.swift Resources/AppIcon.png "$OUT/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  echo "    icon generated"
else
  echo "    (icon generation skipped)"; sed -i '' '/CFBundleIconFile/d' "$OUT/Contents/Info.plist"
fi

echo "==> Signing (identity: ${IDENTITY/#-/ad-hoc})"
# Hardened runtime: otherwise DYLD_INSERT_LIBRARIES lets other code inherit the Accessibility grant.
# Notarization requires a secure timestamp; other builds skip it so they work offline.
if [[ "$IDENTITY" == "Developer ID Application"* ]]; then TIMESTAMP="--timestamp"; else TIMESTAMP="--timestamp=none"; fi
# Sign Sparkle inside-out with our identity, then the app (hardened-runtime library validation needs one team).
SPARKLE="$OUT/Contents/Frameworks/Sparkle.framework"
for part in "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE"; do
  codesign --force --sign "$IDENTITY" --options runtime "$TIMESTAMP" "$part"
done
# Ad-hoc signatures carry no Team ID, so library validation would refuse Sparkle; real identities keep it on.
ENTITLEMENTS=()
if [[ "$IDENTITY" == "-" ]]; then
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" build/adhoc.entitlements >/dev/null 2>&1 || true
  ENTITLEMENTS=(--entitlements build/adhoc.entitlements)
fi
codesign --force --sign "$IDENTITY" --identifier io.github.pisitpong22.LazyClick --options runtime "$TIMESTAMP" ${ENTITLEMENTS[@]+"${ENTITLEMENTS[@]}"} "$OUT"
codesign --verify --verbose=1 "$OUT"

if [[ "$IDENTITY" == "Developer ID Application"* ]]; then
  ZIP="build/${APP_NAME}.zip"
  echo "==> Notarizing (takes a few minutes)"
  ditto -c -k --keepParent "$OUT" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$APP_NAME" --wait
  # notarytool can exit 0 on a rejected submission; stapler fails if there is no ticket.
  xcrun stapler staple "$OUT"
  spctl --assess --type execute --verbose "$OUT"
  # Zip again so the download carries the stapled ticket.
  rm -f "$ZIP"
  ditto -c -k --keepParent "$OUT" "$ZIP"
  echo "==> Building and notarizing the disk image (the download for new users; Sparkle keeps using the zip)"
  DMG="build/${APP_NAME}.dmg"
  scripts/make_dmg.sh "$OUT" "$DMG"
  codesign --sign "$IDENTITY" --timestamp "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$APP_NAME" --wait
  xcrun stapler staple "$DMG"
  echo "==> Writing appcast (signs the zip with the Sparkle key in your login keychain)"
  APPCAST_DIR="build/appcast"
  rm -rf "$APPCAST_DIR" && mkdir -p "$APPCAST_DIR" && cp "$ZIP" "$APPCAST_DIR/"
  .build/artifacts/sparkle/Sparkle/bin/generate_appcast \
    --download-url-prefix "https://github.com/pisitpong22/LazyClick/releases/download/v${VERSION}/" "$APPCAST_DIR"
  cp "$APPCAST_DIR/appcast.xml" build/appcast.xml
  echo "Release zip: $PWD/$ZIP"
  echo "Upload all three to the v${VERSION} release: $PWD/$ZIP $PWD/$DMG $PWD/build/appcast.xml"
fi

echo "==> Architecture: $(lipo -archs "$OUT/Contents/MacOS/$BIN_NAME")"
echo "==> Size: $(du -sh "$OUT" | cut -f1)"
echo "Built: $PWD/$OUT"
# Quit and delete first: cp -R over a running signed app gets it killed and open fails with -609.
echo "Install: pkill -x $BIN_NAME; rm -rf \"/Applications/${APP_NAME}.app\" && cp -R \"$OUT\" /Applications/ && open \"/Applications/${APP_NAME}.app\""
