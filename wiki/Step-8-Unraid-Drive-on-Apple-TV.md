# Step 8 — Unraid Drive on Apple TV

The same **Unraid Drive** (universal purchase) also runs on Apple TV (tvOS 17 or later). There is no Files app on tvOS, so the TV is a **media browser**: your shares → folders → photos, music and video played straight from the NAS through your **unraid-gateway**, with **your Unraid user's permissions** (the gateway shows only the shares that user may see). Nothing is stored on the TV except the credentials.

## Pairing (nothing to type on the remote)

1. Open Unraid Drive on the Apple TV: it shows a **6-digit code**.
2. On your iPhone, iPad or Mac open Unraid Drive › Settings › **Pair an Apple TV**, enter the code and choose the server.
3. Within a few seconds the TV shows *Paired* and lists the server.

How it works: the phone encrypts the server (URL, mode, Cloudflare token, Unraid user and password, API key) with a key derived from the code (AES-GCM) and drops it in your iCloud Key-Value Storage; the TV reads it, decrypts, stores the secrets in its own Keychain and deletes the record. iCloud only ever sees ciphertext; both devices must use the same Apple Account. Curious first? *Try the demo* on the TV shows sample folders offline.

## Using it

| | |
|---|---|
| Browse | shares and folders as cards; click to open |
| Photos | JPEG, HEIC, PNG, GIF… shown full screen; **Menu** or **Play/Pause** to go back |
| Video | MP4, MOV, M4V, HEVC — native player with scrubbing (the gateway streams with HTTP ranges) |
| Music | MP3, AAC, M4A, WAV, AIFF |
| Other files | listed but not openable on the TV (documents, archives, MKV/AVI rips: Apple TV has no decoder for them — use Infuse or VLC over SMB for those) |
| Dashboard | array state and usage, parity check, CPU/memory, unread notifications |
| Remove | Server page › *Remove this server from the TV* (files stay on the NAS) |

## Troubleshooting

- **"Credentials for this server are missing on the TV"**: pair again from the phone; the TV keeps only local copies.
- **Code never accepted**: both devices must be signed in to the same iCloud account with iCloud Drive on; press *New code* and retry. The blob expires when the TV reads it.
- **Video does not play**: check the format (above). HEVC 10-bit/Dolby Vision play on Apple TV 4K; AV1 only on the 3rd generation.

## Publishing note (App Store Connect)

The tvOS listing cannot be submitted with only a Privacy Policy **URL**: Apple TV has no browser, so App Store Connect requires **App Information › Privacy Policy Text** in every locale. The texts live in `AppStore/store_meta.py` (`PRIVACY_TEXT`) and mirror `PRIVACY.md`.
