#!/bin/zsh
# Builds a universal, Developer ID-signed macOS installer: dist/Ember-<version>.pkg
#
#   Scripts/make-installer.sh                                   # build + sign
#   NOTARY_PROFILE=<keychain profile> Scripts/make-installer.sh # build + sign + notarize + staple
#
# Signing settings come from .env in the repo root (copy .env.example). Variables already set in
# the environment take precedence over .env.
#
# Create a notary profile once with:
#   xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team-id> --password <app-specific password>
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

source Scripts/env.zsh
require TEAM_ID
require DEVELOPER_NAME

TEAM="$TEAM_ID"
APP_IDENTITY="${APP_IDENTITY:-Developer ID Application: $DEVELOPER_NAME ($TEAM)}"
PKG_IDENTITY="${PKG_IDENTITY:-Developer ID Installer: $DEVELOPER_NAME ($TEAM)}"
VERSION=$(awk '/MARKETING_VERSION:/ { print $2 }' project.yml)
BUILD="build/release"
STAGE="$BUILD/pkgroot"
DIST="dist"
PRODUCT="$DIST/Ember-$VERSION.pkg"

step() { print -P "%B==> $1%b"; }

step "Cleaning"
rm -rf "$BUILD"
mkdir -p "$STAGE" "$DIST"

step "Running DSP tests"
Scripts/run-dsp-tests.sh | tail -1

step "Building Ember $VERSION (Release, universal, Developer ID, hardened runtime)"
Scripts/generate-project.sh --quiet
xcodebuild -project Ember.xcodeproj -scheme Ember_macOS -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$BUILD/DerivedData" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$APP_IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM" ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build -quiet
APP="$BUILD/DerivedData/Build/Products/Release/Ember.app"

step "Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP"
for bundle in "$APP" "$APP/Contents/PlugIns/EmberExtension.appex"; do
    # Capture first: with pipefail, `grep -q` closing the pipe early would fail the pipeline.
    signature=$(codesign -dvv "$bundle" 2>&1)
    entitlements=$(codesign -d --entitlements - "$bundle" 2>/dev/null)
    [[ "$signature" == *"Authority=Developer ID Application"* ]] || { echo "not Developer ID signed: $bundle"; exit 1; }
    [[ "$signature" == *"(runtime)"* ]] || { echo "hardened runtime missing: $bundle"; exit 1; }
    [[ "$signature" == *"Timestamp="* ]] || { echo "secure timestamp missing: $bundle"; exit 1; }
    [[ "$entitlements" == *"com.apple.security.app-sandbox"* ]] || { echo "sandbox entitlement missing: $bundle"; exit 1; }
    [[ "$entitlements" != *"get-task-allow"* ]] || { echo "debug entitlement present: $bundle"; exit 1; }
done
lipo -archs "$APP/Contents/PlugIns/EmberExtension.appex/Contents/MacOS/EmberExtension"

step "Building component package"
ditto "$APP" "$STAGE/Ember.app"
pkgbuild --analyze --root "$STAGE" "$BUILD/components.plist" >/dev/null
# Never relocate: otherwise Installer "updates" a copy found elsewhere (e.g. a build folder).
plutil -replace 0.BundleIsRelocatable -bool NO "$BUILD/components.plist"
chmod 755 Installer/scripts/postinstall
pkgbuild --root "$STAGE" \
    --component-plist "$BUILD/components.plist" \
    --install-location /Applications \
    --scripts Installer/scripts \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    "$BUILD/Ember-component.pkg" >/dev/null

step "Building signed product archive"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" -e "s/__ORGANIZATION__/$ORGANIZATION/g" \
    Installer/distribution.xml > "$BUILD/distribution.xml"
productbuild --distribution "$BUILD/distribution.xml" \
    --resources Installer/resources \
    --package-path "$BUILD" \
    --sign "$PKG_IDENTITY" --timestamp \
    "$PRODUCT" >/dev/null
pkgutil --check-signature "$PRODUCT" | head -3

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    step "Notarizing (this usually takes a few minutes)"
    xcrun notarytool submit "$PRODUCT" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$PRODUCT"
    spctl --assess --type install --verbose=2 "$PRODUCT"
else
    print "\nNot notarized (set NOTARY_PROFILE to notarize). Gatekeeper will warn on other Macs until it is."
fi

step "Done: $PRODUCT ($(du -h "$PRODUCT" | cut -f1))"
