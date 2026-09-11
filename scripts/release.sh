#!/bin/zsh
set -o pipefail
cd "$(dirname "$0")/.."
ISSUER="${ASC_ISSUER:?set ASC_ISSUER to the App Store Connect issuer id}"
# Signing: the Xcode account session handles iOS/visionOS (cloud-managed Apple Distribution certificate);
# macOS needs the local "3rd Party Mac Developer Application/Installer" certificates (kit: MacDistribution/).
# The API key has no cloud-signing permission, so it is used only by altool.
AUTH=(-allowProvisioningUpdates)
for PLAT in ${=PLATFORMS:-iOS visionOS macOS tvOS}; do   # PLATFORMS="iOS macOS" to restrict
  echo "=== archive $PLAT"
  rm -rf build/UnraidDrive-$PLAT.xcarchive build/export-$PLAT
  SCHEME=UnraidDrive; [ "$PLAT" = macOS ] && SCHEME=UnraidDriveMac; [ "$PLAT" = tvOS ] && SCHEME=UnraidDriveTV
  # tvOS: the Release configuration of UnraidDriveTV signs manually with the App Store profile (project.yml).
  EXTRA=()
  xcodebuild archive -project UnraidDrive.xcodeproj -scheme $SCHEME -destination "generic/platform=$PLAT" \
    -archivePath build/UnraidDrive-$PLAT.xcarchive -derivedDataPath build/dd-$PLAT "${AUTH[@]}" "${EXTRA[@]}" 2>&1 | grep -E "error:|ARCHIVE"
  [ -d build/UnraidDrive-$PLAT.xcarchive ] || { echo "archive $PLAT failed"; exit 1; }
  for try in 1 2 3; do
    echo "=== export $PLAT (try $try)"
    EO=ExportOptions-$PLAT.plist; [ -f "$EO" ] || EO=ExportOptions.plist   # manual signing with the API-created profiles when present
    xcodebuild -exportArchive -archivePath build/UnraidDrive-$PLAT.xcarchive -exportOptionsPlist "$EO" \
      -exportPath build/export-$PLAT "${AUTH[@]}" 2>&1 | grep -E "error:|EXPORT" && break
    sleep 10
  done
  if [ "$PLAT" = macOS ]; then PKG=$(ls build/export-$PLAT/*.pkg | head -1); else PKG=$(ls build/export-$PLAT/*.ipa | head -1); fi
  ls "$PKG" || exit 1
  echo "=== upload $PLAT"
  T=ios; [ "$PLAT" = visionOS ] && T=visionos; [ "$PLAT" = macOS ] && T=macos; [ "$PLAT" = tvOS ] && T=appletvos
  xcrun altool --upload-app -f "$PKG" -t $T --apiKey Z9NY29WQ4M --apiIssuer "$ISSUER" 2>&1 | grep -v "^$" | tail -5
done
echo "=== RELEASE DONE"
