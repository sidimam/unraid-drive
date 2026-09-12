# Step 8 — Unraid Drive on Apple TV

The same **Unraid Drive** (universal purchase) also runs on Apple TV (tvOS 17 or later). There is no Files app on tvOS, so the TV is a **media browser**: your shares → folders → photos, music and video played straight from the NAS through your **unraid-gateway**, with **your Unraid user's permissions** (the gateway shows only the shares that user may see). Nothing is stored on the TV except the credentials.

## Pairing (nothing to type on the remote)

1. Open Unraid Drive on the Apple TV: it shows a **6-digit code**.
2. On your iPhone, iPad or Mac open Unraid Drive › Settings › **Pair an Apple TV**, enter the code and choose what to send: **all servers** (default when you have more than one — the whole configuration, like a restore) or a single server.
3. Within a few seconds the TV shows *Paired* and lists the servers; each one keeps the shares you chose on the phone.

**Configuration found in iCloud.** If your other devices saved the configuration in iCloud (Settings › iCloud in the app), a new or reset Apple TV opens on *Configuration found in iCloud: N servers* with their names. Apple TV has no iCloud Keychain, so the credentials cannot be read there: the same pairing code brings them, and the TV registers itself on every gateway again (build 30+).

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

## Shares to show

Right after pairing, the TV shows the *Shares to show* list for the new server, pre-filled with the choice of the device that paired it. Change it later on the TV under the server › **Shares to show** (*All shares* or a tick per share). Hidden shares are not listed in *Browse shares*; the gateway still applies your Unraid user's permissions.

## The file explorer

*Browse shares* is a proper explorer: list or grid (button at the top right), sort by name, date or size, item count, and a long-press menu per item with **Info**, **Open**, **Copy**, **Cut**, **Paste into folder**, **Rename**, **Select** and **Delete** (with confirmation); **Select** (also in the header) turns on multi-selection — a checkmark per item, *Select all*, then **Copy**, **Cut** or **Delete** the whole selection, one confirmation for the lot; **New folder** sits in the toolbar (a *Paste* button appears at the top of a folder when something was copied or cut). Folders open in place; files open in the right viewer: photos, the system player for Apple formats, mpv for everything else, a text viewer for TXT/NFO/Markdown/JSON/CSV/subtitles and other plain-text files, a page viewer for **PDF**, a reader for **EPUB** (text) and **CBZ** comics, and a listing for **ZIP** archives. What the TV cannot open (Office documents, unknown types) shows its details and, when Infuse or VLC are installed on the Apple TV, an **Open in Infuse / Open in VLC** button that hands the file to that app through the gateway's signed media link.

## Formats and the mpv player

Apple formats (MP4, MOV, M4V, HEVC, AAC, MP3, JPEG, HEIC) play with the system player. Everything else — MKV, AVI, WebM, MPEG-TS, VOB, FLAC, OGG, Opus, WMA and more — opens in the built-in **mpv** player (libmpv and FFmpeg, LGPL build, shipped through [MPVKit](https://github.com/mpvkit/MPVKit)): hardware decoding, embedded subtitles and audio tracks, HDR passthrough where the TV supports it. If the system player fails on an Apple-format file, a button hands it to mpv. Siri Remote: play/pause with the play button or a click, left/right ±10 s, Menu closes.

The built-in mpv sends the same headers as the app (bearer token and, if you use it, the Cloudflare Access service token), so it works wherever the app works. Only the hand-off to **Infuse or VLC** needs a header-less link: the app asks `unraid-gateway` (0.6 or later) for a signed **media ticket** valid for that one file for a few hours (nothing secret in the URL, invalidated by a gateway restart). Behind Cloudflare Access, exclude the `/media/*` path from the Access policy for those external players, or use the gateway on the LAN.

## Troubleshooting

- **"Credentials for this server are missing on the TV"**: pair again from the phone; the TV keeps only local copies.
- **Code never accepted**: both devices must be signed in to the same iCloud account with iCloud Drive on; press *New code* and retry. The blob expires when the TV reads it.
- **Video does not play**: check the format (above). HEVC 10-bit/Dolby Vision play on Apple TV 4K; AV1 only on the 3rd generation.
- **"Cannot play this file" with a reason underneath** (build 30+): before mpv starts, the TV fetches the first byte of the file with the app's headers and shows what answered instead of the video — *a web page answered (Cloudflare Access login)* → the service token on the TV is wrong or missing, pair again; *401* → the Unraid API key or user was rejected; *this device was removed from the gateway* → pair again to register it; *the gateway answered 5xx* → look at the gateway log. Streams use a media ticket, so a long film does not stop when the session token expires.

## Publishing note (App Store Connect)

The tvOS listing cannot be submitted with only a Privacy Policy **URL**: Apple TV has no browser, so App Store Connect requires **App Information › Privacy Policy Text** in every locale. The texts live in `AppStore/store_meta.py` (`PRIVACY_TEXT`) and mirror `PRIVACY.md`.
