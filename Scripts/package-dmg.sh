#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
APP_PATH="$PROJECT_ROOT/dist/FastNET.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_ROOT/Packaging/Info.plist")
DMG_PATH="$PROJECT_ROOT/dist/FastNET-$VERSION-macOS.dmg"
BACKGROUND_BUILD="$PROJECT_ROOT/.build/dmg-background.png"
VOLUME_NAME="FastNET"
STAGING_DIR=$(/usr/bin/mktemp -d "/private/tmp/fastnet-dmg-staging.XXXXXX")
WRITABLE_DMG="/private/tmp/FastNET-$VERSION-writable.dmg"
MOUNT_DIR=""
DEVICE=""

cleanup() {
    if [[ -n "$DEVICE" ]]; then
        /usr/bin/hdiutil detach "$DEVICE" -quiet || true
    fi
    /bin/rm -rf "$STAGING_DIR"
    /bin/rm -f "$WRITABLE_DMG"
}
trap cleanup EXIT

"$PROJECT_ROOT/Scripts/package-app.sh"

/bin/mkdir -p "$PROJECT_ROOT/.build" "$STAGING_DIR/.background"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}" \
CLANG_MODULE_CACHE_PATH="/private/tmp/fastnet-dmg-clang-cache" \
/usr/bin/xcrun swift "$PROJECT_ROOT/Scripts/generate-dmg-background.swift" "$BACKGROUND_BUILD"

/usr/bin/ditto "$APP_PATH" "$STAGING_DIR/FastNET.app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"
/usr/bin/ditto "$BACKGROUND_BUILD" "$STAGING_DIR/.background/FastNET-DMG-Background.png"
/usr/bin/ditto "$APP_PATH/Contents/Resources/AppIcon.icns" "$STAGING_DIR/.VolumeIcon.icns"

/bin/rm -f "$WRITABLE_DMG" "$DMG_PATH"
/usr/bin/hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -fs APFS \
    -format UDRW \
    "$WRITABLE_DMG" >/dev/null

ATTACH_OUTPUT=$(/usr/bin/hdiutil attach \
    "$WRITABLE_DMG" \
    -readwrite \
    -noverify \
    -noautoopen)
DEVICE=$(print -r -- "$ATTACH_OUTPUT" | /usr/bin/awk 'NR == 1 { print $1 }')
MOUNT_DIR=$(print -r -- "$ATTACH_OUTPUT" | /usr/bin/awk '/\/Volumes\// { print $NF }' | /usr/bin/tail -1)
if [[ -z "$DEVICE" || -z "$MOUNT_DIR" ]]; then
    print -u2 "Unable to determine mounted disk path"
    exit 1
fi
MOUNT_NAME="${MOUNT_DIR:t}"

/usr/bin/osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$MOUNT_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set sidebar width of container window to 0
        set the bounds of container window to {180, 160, 780, 551}
        set arrangement of icon view options of container window to not arranged
        set icon size of icon view options of container window to 104
        set text size of icon view options of container window to 13
        set background picture of icon view options of container window to file ".background:FastNET-DMG-Background.png"
        set position of item "FastNET.app" of container window to {170, 205}
        set position of item "Applications" of container window to {430, 205}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

if [[ -x "/Applications/Xcode-beta.app/Contents/Developer/Tools/SetFile" ]]; then
    /Applications/Xcode-beta.app/Contents/Developer/Tools/SetFile -a C "$MOUNT_DIR"
elif [[ -x "/usr/bin/SetFile" ]]; then
    /usr/bin/SetFile -a C "$MOUNT_DIR"
fi

/bin/sync
/usr/bin/hdiutil detach "$DEVICE" -quiet
DEVICE=""
/usr/bin/hdiutil convert "$WRITABLE_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
/usr/bin/hdiutil verify "$DMG_PATH"
/usr/bin/shasum -a 256 "$DMG_PATH"

print "Packaged: $DMG_PATH"
