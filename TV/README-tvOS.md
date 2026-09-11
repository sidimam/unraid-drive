# Unraid Drive for Apple TV

Same app name and App Store record (universal purchase). No Files app on tvOS, so the TV is a
media browser: shares → folders → photos, music and video played straight from the gateway
(AVPlayer with the authorized request; the gateway serves HTTP ranges). Connection ONLY through
unraid-gateway, with the user's Unraid login so the gateway applies the share permissions.

Pairing: the TV shows a 6-digit code (`TVPairView`); iPhone/iPad/Mac Settings › *Pair an Apple TV*
encrypts the server + secrets with a key derived from the code (AES-GCM, `TVPairing` in the Kit)
and writes `tv.pair.<code>` to iCloud Key-Value Storage; the TV decrypts, stores the secrets in its
local Keychain (tvOS has no iCloud Keychain) and deletes the key.
