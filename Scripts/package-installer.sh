#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
APP_PATH="$PROJECT_ROOT/dist/FastNET.app"
PRODUCTS_PATH="$PROJECT_ROOT/.build/out/Products/Release"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_ROOT/Packaging/Info.plist")
PKG_PATH="$PROJECT_ROOT/dist/Install-FastNET-$VERSION.pkg"
STAGING_DIR=$(/usr/bin/mktemp -d "/private/tmp/fastnet-pkg-root.XXXXXX")
SIGNING_IDENTITY="${FASTNET_CODESIGN_IDENTITY:--}"
INSTALLER_IDENTITY="${FASTNET_INSTALLER_IDENTITY:-}"

cleanup() {
    /bin/rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

"$PROJECT_ROOT/Scripts/package-app.sh"

/bin/mkdir -p \
    "$STAGING_DIR/Applications" \
    "$STAGING_DIR/Library/PrivilegedHelperTools" \
    "$STAGING_DIR/Library/LaunchDaemons"

/usr/bin/ditto "$APP_PATH" "$STAGING_DIR/Applications/FastNET.app"
/usr/bin/ditto "$PRODUCTS_PATH/FastNETHelper" \
    "$STAGING_DIR/Library/PrivilegedHelperTools/com.fastnet.utility.installer.helper"
/usr/bin/ditto "$PROJECT_ROOT/Packaging/com.fastnet.utility.installer.helper.plist" \
    "$STAGING_DIR/Library/LaunchDaemons/com.fastnet.utility.installer.helper.plist"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    /usr/bin/codesign --force --sign - \
        --identifier com.fastnet.utility.installer.helper \
        "$STAGING_DIR/Library/PrivilegedHelperTools/com.fastnet.utility.installer.helper"
else
    /usr/bin/codesign --force --options runtime --timestamp \
        --sign "$SIGNING_IDENTITY" \
        --identifier com.fastnet.utility.installer.helper \
        "$STAGING_DIR/Library/PrivilegedHelperTools/com.fastnet.utility.installer.helper"
fi

/usr/bin/codesign --verify --strict --verbose=2 \
    "$STAGING_DIR/Library/PrivilegedHelperTools/com.fastnet.utility.installer.helper"

/bin/rm -f "$PKG_PATH"
PKGBUILD_ARGS=(
    --root "$STAGING_DIR"
    --install-location /
    --identifier com.fastnet.utility.installer
    --version "$VERSION"
    --ownership recommended
    --scripts "$PROJECT_ROOT/Packaging/InstallerScripts"
)
if [[ -n "$INSTALLER_IDENTITY" ]]; then
    PKGBUILD_ARGS+=(--sign "$INSTALLER_IDENTITY")
fi
/usr/bin/pkgbuild "${PKGBUILD_ARGS[@]}" "$PKG_PATH"
/usr/sbin/pkgutil --check-signature "$PKG_PATH" || true

print "Packaged: $PKG_PATH"
