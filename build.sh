#!/bin/bash
# Builds "LazyClick.app" (arm64, Release) into ./build and runs the unit tests first.
#
#   ./build.sh              build + test + bundle + ad-hoc sign
#   SKIP_TESTS=1 ./build.sh skip the test run
#   CODESIGN_IDENTITY="Apple Development: Name (TEAMID)" ./build.sh
#                           sign with a stable identity so the Accessibility grant survives rebuilds
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
sed -e "s/__VERSION__/${VERSION}/" -e "s/__BUILD__/${BUILD_NUMBER}/" Resources/Info.plist > "$OUT/Contents/Info.plist"
printf 'APPL????' > "$OUT/Contents/PkgInfo"
strip -x "$OUT/Contents/MacOS/$BIN_NAME" 2>/dev/null || true

if swift scripts/make_icon.swift "$OUT/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  echo "    icon generated"
else
  echo "    (icon generation skipped)"; sed -i '' '/CFBundleIconFile/d' "$OUT/Contents/Info.plist"
fi

echo "==> Signing (identity: ${IDENTITY/#-/ad-hoc})"
codesign --force --sign "$IDENTITY" --identifier io.github.pisitpong22.LazyClick --timestamp=none "$OUT"
codesign --verify --verbose=1 "$OUT"

echo "==> Architecture: $(lipo -archs "$OUT/Contents/MacOS/$BIN_NAME")"
echo "==> Size: $(du -sh "$OUT" | cut -f1)"
echo "Built: $PWD/$OUT"
echo "Install: cp -R \"$OUT\" /Applications/ && open \"/Applications/${APP_NAME}.app\""
