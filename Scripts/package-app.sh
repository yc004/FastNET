#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
APP_PATH="$PROJECT_ROOT/dist/FastNET.app"
PRODUCTS_PATH="$PROJECT_ROOT/.build/out/Products/Release"
ASSET_OUTPUT="$PROJECT_ROOT/.build/app-icon-output"
DEVELOPER_ROOT="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
SIGNING_IDENTITY="${FASTNET_CODESIGN_IDENTITY:--}"

if [[ "$APP_PATH" != "$PROJECT_ROOT/dist/FastNET.app" ]]; then
    print -u2 "Refusing to package an unexpected path: $APP_PATH"
    exit 1
fi

DEVELOPER_DIR="$DEVELOPER_ROOT" \
CLANG_MODULE_CACHE_PATH="/private/tmp/fastnet-release-clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="/private/tmp/fastnet-release-spm-cache" \
swift build \
    --configuration release \
    --disable-sandbox \
    --build-system swiftbuild \
    --jobs 1

/bin/rm -rf "$APP_PATH" "$ASSET_OUTPUT"
/bin/mkdir -p \
    "$APP_PATH/Contents/MacOS" \
    "$APP_PATH/Contents/Resources" \
    "$ASSET_OUTPUT"

/usr/bin/ditto "$PRODUCTS_PATH/FastNET" "$APP_PATH/Contents/MacOS/FastNET"
/usr/bin/ditto "$PRODUCTS_PATH/FastNET_FastNET.bundle" "$APP_PATH/Contents/Resources/FastNET_FastNET.bundle"
/usr/bin/ditto "$PROJECT_ROOT/Packaging/Info.plist" "$APP_PATH/Contents/Info.plist"

for icon in "$PROJECT_ROOT"/Sources/FastNET/Resources/AppIcon.iconset/*.png; do
    /usr/bin/ditto "$icon" "$PROJECT_ROOT/Packaging/Assets.xcassets/AppIcon.appiconset/${icon:t}"
done

DEVELOPER_DIR="$DEVELOPER_ROOT" /usr/bin/xcrun actool \
    "$PROJECT_ROOT/Packaging/Assets.xcassets" \
    --compile "$ASSET_OUTPUT" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ASSET_OUTPUT/asset-info.plist"

/usr/bin/ditto "$ASSET_OUTPUT/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    print -u2 "Warning: creating an ad-hoc signed local development build."
    /usr/bin/codesign --force --sign - \
        --identifier com.fastnet.utility \
        "$APP_PATH"
else
    /usr/bin/codesign --force --options runtime --timestamp \
        --sign "$SIGNING_IDENTITY" \
        --identifier com.fastnet.utility \
        "$APP_PATH"
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"

print "Packaged: $APP_PATH"
