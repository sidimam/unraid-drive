#!/bin/zsh
set -o pipefail
cd "$(dirname "$0")/.."
ISSUER="${ASC_ISSUER:?set ASC_ISSUER to the App Store Connect issuer id}"
for PLAT in ${PLATFORMS:-iOS visionOS macOS}; do
  echo "=== archive $PLAT"
  rm -rf build/UnraidDrive-$PLAT.xcarchive build/export-$PLAT
  xcodebuild archive -project UnraidDrive.xcodeproj -scheme UnraidDrive -destination "generic/platform=$PLAT" \
    -archivePath build/UnraidDrive-$PLAT.xcarchive -derivedDataPath build/dd-$PLAT -allowProvisioningUpdates 2>&1 | grep -E "error:|ARCHIVE" || exit 1
  for try in 1 2 3; do
    echo "=== export $PLAT (try $try)"
    xcodebuild -exportArchive -archivePath build/UnraidDrive-$PLAT.xcarchive -exportOptionsPlist ExportOptions.plist \
      -exportPath build/export-$PLAT -allowProvisioningUpdates 2>&1 | grep -E "error:|EXPORT" && break
    sleep 10
  done
  if [ "$PLAT" = macOS ]; then PKG=$(ls build/export-$PLAT/*.pkg | head -1); else PKG=build/export-$PLAT/UnraidDrive.ipa; fi
  ls "$PKG" || exit 1
  echo "=== upload $PLAT"
  T=ios; [ "$PLAT" = visionOS ] && T=visionos; [ "$PLAT" = macOS ] && T=macos
  xcrun altool --upload-app -f "$PKG" -t $T --apiKey Z9NY29WQ4M --apiIssuer "$ISSUER" 2>&1 | grep -v "^$" | tail -5
done
echo "=== RELEASE DONE"
