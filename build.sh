#!/bin/bash
# Builds "LazyClick.app" (arm64, Release) into ./build and runs the unit tests first.
#
#   ./build.sh              build + test + bundle + ad-hoc sign
#   SKIP_TESTS=1 ./build.sh skip the test run
#   CODESIGN_IDENTITY="Apple Development: Name (TEAMID)" ./build.sh
#                           sign with a stable identity so the Accessibility grant survives rebuilds
#   CODESIGN_IDENTITY="Developer ID Application" ./build.sh
#                           release: also notarize + staple and write build/LazyClick.zip
#                           (once first: xcrun notarytool store-credentials LazyClick)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="LazyClick"
BIN_NAME="LazyClick"
VERSION="${VERSION:-1.0.0}"
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
codesign --force --sign "$IDENTITY" --identifier io.github.pisitpong22.LazyClick --options runtime "$TIMESTAMP" "$OUT"
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
  echo "Release zip: $PWD/$ZIP"
fi

echo "==> Architecture: $(lipo -archs "$OUT/Contents/MacOS/$BIN_NAME")"
echo "==> Size: $(du -sh "$OUT" | cut -f1)"
echo "Built: $PWD/$OUT"
# Quit and delete first: cp -R over a running signed app gets it killed and open fails with -609.
echo "Install: pkill -x $BIN_NAME; rm -rf \"/Applications/${APP_NAME}.app\" && cp -R \"$OUT\" /Applications/ && open \"/Applications/${APP_NAME}.app\""
