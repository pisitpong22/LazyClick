#!/bin/bash
# Builds the drag-to-install disk image: the app, an Applications shortcut and an arrow between them.
#   scripts/make_dmg.sh build/LazyClick.app build/LazyClick.dmg
# Lays out the window through Finder, so the first run asks to let Terminal control Finder.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$1"
DMG="$2"
NAME="$(basename "$APP" .app)"
WORK="build/dmg"
RW="$WORK/rw.dmg"
rm -rf "$WORK" "$DMG"
mkdir -p "$WORK/stage/.background"

ditto "$APP" "$WORK/stage/$NAME.app"
ln -s /Applications "$WORK/stage/Applications"
swift scripts/make_dmg_background.swift "$WORK/bg.png" 1
swift scripts/make_dmg_background.swift "$WORK/bg@2x.png" 2
tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out "$WORK/stage/.background/background.tiff" 2>/dev/null
cp "$APP/Contents/Resources/AppIcon.icns" "$WORK/stage/.VolumeIcon.icns"

hdiutil create -quiet -volname "$NAME" -srcfolder "$WORK/stage" -fs HFS+ -format UDRW -ov "$RW"
MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\// {print $NF}')"
trap 'hdiutil detach -quiet "$MOUNT" 2>/dev/null || true' EXIT
SetFile -a C "$MOUNT" # use .VolumeIcon.icns

# Icon positions must match the arrow drawn by make_dmg_background.swift.
osascript - "$(basename "$MOUNT")" "$NAME.app" <<'EOF'
on run argv
    tell application "Finder"
        tell disk (item 1 of argv)
            open
            set w to container window
            set current view of w to icon view
            set toolbar visible of w to false
            set statusbar visible of w to false
            set bounds of w to {200, 120, 860, 580} -- 400pt of background plus title and path bars
            set o to icon view options of w
            set arrangement of o to not arranged
            set icon size of o to 128
            set text size of o to 13
            set background picture of o to file ".background:background.tiff"
            set position of item (item 2 of argv) of w to {180, 180}
            set position of item "Applications" of w to {480, 180}
            close
            open
            delay 1
            close
        end tell
    end tell
end run
EOF

sync
hdiutil detach -quiet "$MOUNT"
trap - EXIT
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -rf "$WORK"
echo "Disk image: $PWD/$DMG"
