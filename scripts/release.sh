#!/bin/zsh
set -o pipefail
cd "$(dirname "$0")/.."
ISSUER="${ASC_ISSUER:?set ASC_ISSUER to the App Store Connect issuer id}"
# Signing: the Xcode account session handles iOS/visionOS (cloud-managed Apple Distribution certificate);
# macOS needs the local "3rd Party Mac Developer Application/Installer" certificates (kit: MacDistribution/).
# The API key has no cloud-signing permission, so it is used only by altool.
AUTH=(-allowProvisioningUpdates)
# Intermediates, archives and exports live OUTSIDE the repo: inside Google Drive the sync client adds
# extended attributes to every file and CodeSign fails with "resource fork, Finder information, or
# similar detritus not allowed". Override with DD_ROOT if needed.
DD_ROOT="${DD_ROOT:-$HOME/Library/Caches/UnraidDrive-build}"; mkdir -p "$DD_ROOT"
xattr -cr App FileProvider Packages TV Shared project.yml UnraidDrive.xcodeproj 2>/dev/null
for PLAT in ${=PLATFORMS:-iOS visionOS macOS tvOS}; do   # PLATFORMS="iOS macOS" to restrict
  echo "=== archive $PLAT"
  rm -rf "$DD_ROOT/UnraidDrive-$PLAT.xcarchive" "$DD_ROOT/export-$PLAT"
  SCHEME=UnraidDrive; [ "$PLAT" = macOS ] && SCHEME=UnraidDriveMac; [ "$PLAT" = tvOS ] && SCHEME=UnraidDriveTV
  # tvOS: the Release configuration of UnraidDriveTV signs manually with the App Store profile (project.yml).
  EXTRA=()
  xcodebuild archive -project UnraidDrive.xcodeproj -scheme $SCHEME -destination "generic/platform=$PLAT" \
    -archivePath "$DD_ROOT/UnraidDrive-$PLAT.xcarchive" -derivedDataPath "$DD_ROOT/dd-$PLAT" "${AUTH[@]}" "${EXTRA[@]}" 2>&1 | tee "$DD_ROOT/archive-$PLAT.log" | grep -E "error:|detritus|ARCHIVE"
  [ -d "$DD_ROOT/UnraidDrive-$PLAT.xcarchive" ] || { echo "archive $PLAT failed (full log: $DD_ROOT/archive-$PLAT.log)"; exit 1; }
  for try in 1 2 3; do
    echo "=== export $PLAT (try $try)"
    EO=ExportOptions-$PLAT.plist; [ -f "$EO" ] || EO=ExportOptions.plist   # manual signing with the API-created profiles when present
    xcodebuild -exportArchive -archivePath "$DD_ROOT/UnraidDrive-$PLAT.xcarchive" -exportOptionsPlist "$EO" \
      -exportPath "$DD_ROOT/export-$PLAT" "${AUTH[@]}" 2>&1 | grep -E "error:|EXPORT" && break
    sleep 10
  done
  if [ "$PLAT" = macOS ]; then PKG=$(ls "$DD_ROOT"/export-$PLAT/*.pkg | head -1); else PKG=$(ls "$DD_ROOT"/export-$PLAT/*.ipa | head -1); fi
  ls "$PKG" || exit 1
  echo "=== upload $PLAT"
  T=ios; [ "$PLAT" = visionOS ] && T=visionos; [ "$PLAT" = macOS ] && T=macos; [ "$PLAT" = tvOS ] && T=appletvos
  xcrun altool --upload-app -f "$PKG" -t $T --apiKey Z9NY29WQ4M --apiIssuer "$ISSUER" 2>&1 | grep -v "^$" | tail -5
done
echo "=== RELEASE DONE"
