#!/bin/zsh
# Developer ID build of Unraid Drive for macOS, outside the App Store (GitHub Releases + Homebrew cask).
# Archives the Mac scheme, exports with Developer ID, notarizes app and DMG, staples both.
# Usage: ASC_ISSUER=… ASC_KEY=/path/AuthKey_Z9NY29WQ4M.p8 scripts/make_dmg.sh   → build/Unraid-Drive-<version>.dmg
set -o pipefail
cd "$(dirname "$0")/.."
ISSUER="${ASC_ISSUER:?set ASC_ISSUER}"; KEY="${ASC_KEY:?set ASC_KEY to the .p8 path}"; KEY_ID="${ASC_KEY_ID:-Z9NY29WQ4M}"
VERSION=$(grep -m1 'MARKETING_VERSION' project.yml | sed 's/.*"\(.*\)".*/\1/'); BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' project.yml | sed 's/.*"\(.*\)".*/\1/')
# Intermediates live OUTSIDE the repo (Google Drive adds xattrs → CodeSign "detritus not allowed"); only the DMG lands in build/.
DD_ROOT="${DD_ROOT:-$HOME/Library/Caches/UnraidDrive-build}"; mkdir -p "$DD_ROOT" build
APP="$DD_ROOT/export-devid/Unraid Drive.app"; DMG="build/Unraid-Drive-$VERSION-$BUILD.dmg"
# Reuse an exported app only if it is this very build (a stale export would ship the previous version).
EXPORTED=$( [ -d "$APP" ] && /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist" 2>/dev/null || echo none )
if [ "$EXPORTED" != "$BUILD" ]; then
  echo "=== archive + export build $BUILD (exported: $EXPORTED)"
  rm -rf "$DD_ROOT/UnraidDrive-macOS.xcarchive" "$DD_ROOT/export-devid"
  xattr -cr App FileProvider Packages TV Shared project.yml UnraidDrive.xcodeproj 2>/dev/null
  AUTH=(-allowProvisioningUpdates)   # Developer ID Application certificate is in the login keychain
  xcodebuild archive -project UnraidDrive.xcodeproj -scheme UnraidDriveMac -destination "generic/platform=macOS" \
    -archivePath "$DD_ROOT/UnraidDrive-macOS.xcarchive" -derivedDataPath "$DD_ROOT/dd-macOS" "${AUTH[@]}" 2>&1 | tee "$DD_ROOT/archive-devid.log" | grep -E "error:|detritus|ARCHIVE"
  xcodebuild -exportArchive -archivePath "$DD_ROOT/UnraidDrive-macOS.xcarchive" -exportOptionsPlist ExportOptions-DeveloperID.plist \
    -exportPath "$DD_ROOT/export-devid" "${AUTH[@]}" 2>&1 | grep -E "error:|EXPORT"
  [ -d "$APP" ] || { echo "export failed"; exit 1; }
  echo "=== notarize app"
  ditto -c -k --keepParent "$APP" "$DD_ROOT/UnraidDrive-notarize.zip"
  xcrun notarytool submit "$DD_ROOT/UnraidDrive-notarize.zip" --key "$KEY" --key-id "$KEY_ID" --issuer "$ISSUER" --wait | grep -E "id:|status:"
  xcrun stapler staple "$APP" | tail -1
fi
echo "=== dmg"
rm -rf "$DD_ROOT/dmg-root" "$DMG"; mkdir -p "$DD_ROOT/dmg-root"
ditto "$APP" "$DD_ROOT/dmg-root/Unraid Drive.app"; ln -s /Applications "$DD_ROOT/dmg-root/Applications"
hdiutil create -volname "Unraid Drive" -srcfolder "$DD_ROOT/dmg-root" -ov -format UDZO "$DMG" | tail -1
DEVID="${DEVID:-Developer ID Application: SIMONE DI MAMBRO (X5SR67A8AL)}"
codesign --force --sign "$DEVID" --timestamp "$DMG" || { echo "dmg codesign failed"; exit 1; }
echo "=== notarize dmg"
xcrun notarytool submit "$DMG" --key "$KEY" --key-id "$KEY_ID" --issuer "$ISSUER" --wait | grep -E "id:|status:"
xcrun stapler staple "$DMG" | tail -1
spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 | head -1
shasum -a 256 "$DMG"
echo "=== DMG DONE $DMG"
