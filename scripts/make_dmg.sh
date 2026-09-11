#!/bin/zsh
# Developer ID build of Unraid Drive for macOS, outside the App Store (GitHub Releases + Homebrew cask).
# Archives the Mac scheme, exports with Developer ID, notarizes app and DMG, staples both.
# Usage: ASC_ISSUER=… ASC_KEY=/path/AuthKey_Z9NY29WQ4M.p8 scripts/make_dmg.sh   → build/Unraid-Drive-<version>.dmg
set -o pipefail
cd "$(dirname "$0")/.."
ISSUER="${ASC_ISSUER:?set ASC_ISSUER}"; KEY="${ASC_KEY:?set ASC_KEY to the .p8 path}"; KEY_ID="${ASC_KEY_ID:-Z9NY29WQ4M}"
VERSION=$(grep -m1 'MARKETING_VERSION' project.yml | sed 's/.*"\(.*\)".*/\1/'); BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' project.yml | sed 's/.*"\(.*\)".*/\1/')
APP="build/export-devid/Unraid Drive.app"; DMG="build/Unraid-Drive-$VERSION-$BUILD.dmg"
if [ ! -d "$APP" ]; then
  rm -rf build/UnraidDrive-macOS.xcarchive build/export-devid
  AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER")
  xcodebuild archive -project UnraidDrive.xcodeproj -scheme UnraidDriveMac -destination "generic/platform=macOS" \
    -archivePath build/UnraidDrive-macOS.xcarchive -derivedDataPath build/dd-macOS "${AUTH[@]}" 2>&1 | grep -E "error:|ARCHIVE"
  xcodebuild -exportArchive -archivePath build/UnraidDrive-macOS.xcarchive -exportOptionsPlist ExportOptions-DeveloperID.plist \
    -exportPath build/export-devid "${AUTH[@]}" 2>&1 | grep -E "error:|EXPORT"
  [ -d "$APP" ] || { echo "export failed"; exit 1; }
  echo "=== notarize app"
  ditto -c -k --keepParent "$APP" build/UnraidDrive-notarize.zip
  xcrun notarytool submit build/UnraidDrive-notarize.zip --key "$KEY" --key-id "$KEY_ID" --issuer "$ISSUER" --wait | grep -E "id:|status:"
  xcrun stapler staple "$APP" | tail -1
fi
echo "=== dmg"
rm -rf build/dmg-root "$DMG"; mkdir -p build/dmg-root
ditto "$APP" "build/dmg-root/Unraid Drive.app"; ln -s /Applications build/dmg-root/Applications
hdiutil create -volname "Unraid Drive" -srcfolder build/dmg-root -ov -format UDZO "$DMG" | tail -1
DEVID="${DEVID:-Developer ID Application: SIMONE DI MAMBRO (X5SR67A8AL)}"
codesign --force --sign "$DEVID" --timestamp "$DMG" || { echo "dmg codesign failed"; exit 1; }
echo "=== notarize dmg"
xcrun notarytool submit "$DMG" --key "$KEY" --key-id "$KEY_ID" --issuer "$ISSUER" --wait | grep -E "id:|status:"
xcrun stapler staple "$DMG" | tail -1
spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 | head -1
shasum -a 256 "$DMG"
echo "=== DMG DONE $DMG"
