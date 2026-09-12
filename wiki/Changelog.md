# Changelog

All notable changes to Unraid Drive. The server side has its own changelog in [unraid-gateway](https://github.com/sidimam/unraid-gateway/wiki/Changelog).

## 1.3 (build 34) — 2026-09-12

- **Files / Finder location maintained automatically.** On the first launch and after every update the app, by itself and for every server: checks the connection to the gateway with the stored credentials, **rebuilds the Files app / Finder location** (removed and registered again, so the system starts from a clean database that matches the extension) and nudges it. The manual *Refresh the Files app / Finder location* and *Rebuild the location* rows are gone; the server page now shows **Files location / Finder location: checked and rebuilt automatically (build N, date)**. If the gateway cannot be reached, or the credentials have not arrived from iCloud Keychain yet, the row says *Automatic check pending* with the reason and a *Check now* button, and the pass is repeated every time the app becomes active until it succeeds. A server you add gets a fresh location, so nothing runs for it until the next update.

## 1.3 (build 33) — 2026-09-12

- **Multi-selection in the explorer, on every device.** *Select* (toolbar button, or *Select* in an item's menu) turns on Select mode: tick as many files and folders as you like (*Select all* in the toolbar; ⌘/⇧-click on the Mac), the title counts them, and the bar at the bottom applies **Copy**, **Cut**, **Move…**, **Copy to…**, **Download**, **Share…** and **Delete** to the whole selection (one confirmation that names the count). The menu of a selected item offers the same actions. Operations run one item after the other with a progress line; a failure does not stop the rest and the errors are listed at the end (they were silent before when the folder was not empty). Paste handles several items too. On Apple TV: *Select* in the header or in the long-press menu, a checkmark per item, *Select all*, *Copy*, *Cut*, *Delete*, *Done*.
- **Download.** New in the item menu and in the selection bar: the files (folders included, recursively) are fetched from the gateway and the system asks where to save them — the Files picker on iPhone, iPad and Vision Pro, a Save panel on the Mac. *Share…* also takes several files at once.
- **Mac: start without a window.** New switch in Preferences › App settings and in the menu bar panel: the app launches in the menu bar only (with *Show only in the menu bar*) or in the menu bar plus the Dock, with no window; *Open Unraid Drive* in the panel or a click on the Dock icon brings it back. Launching at login always starts this way. A first launch, or a new build whose walkthrough is due, still opens the window.

## 1.3 (build 32) — 2026-09-12

- **Move… / Copy to… now confirm the destination.** The folder picker has a fixed bar at the bottom that names the folder that is open (*Destination: /documents/Invoices*) and a big **Move here** / **Copy here** button; at the root it explains that a share must be opened first. Before, the only confirmation was a *Choose* item in the toolbar of the pushed folder, which the Mac did not show inside the sheet — so a move could never be confirmed there. Cancel now closes the picker on every platform (it used to step back one folder).
- **One “Open” for every file.** The context menu no longer has *Play with mpv*: *Open* picks the right viewer by itself (mpv for MKV, AVI, WebM, FLAC…, the EPUB, comic and archive readers, Quick Look for everything else). *Quick Look* stays as a separate entry only where *Open* does something different.

## 1.3 (build 31) — 2026-09-11

- **Mac: crash when playing MKV, AVI and the other mpv formats — fixed.** The notarized app (Developer ID DMG and the App Store build alike) was killed by the hardened runtime as soon as a video loaded: mpv's built-in Lua scripts (stats overlay, console, ytdl hook, auto profiles) run on LuaJIT, whose generated code the kernel refuses (`SIGKILL — Code Signature Invalid` in `load_builtin`). The player now starts mpv with `load-scripts=no` (plus stats overlay, OSD console, auto profiles, OSC and ytdl off) on every platform; the app draws its own controls, so nothing is lost. Verified with the real MKV and AVI from the NAS on Mac, iPhone and Apple TV.

## 1.3 (build 30) — 2026-09-11

- **Restore comes first.** On a new or reinstalled device the walkthrough opens with the configuration found in iCloud (server names listed), restores it — server list from iCloud, API keys, Cloudflare service tokens and Unraid passwords from iCloud Keychain — and then **registers the device on every gateway again** (`login(register: true)`), waiting up to two minutes for the secrets to arrive; one status line per server (registered / waiting / error).
- **Same device after a reinstall.** The device id is remembered in iCloud Key-Value Storage per hardware (`identifierForVendor` on iPhone/iPad/Vision Pro/Apple TV, the platform UUID on the Mac): a reinstall on the same hardware comes back to the gateway as the *same* device, no duplicate in *Devices*. When that is not possible, unraid-gateway 0.9.1 marks the previous entry with the same name and user as **old** (last seen shown) instead of leaving two live entries.
- **Apple TV restore.** With a configuration in iCloud and nothing on the TV, the pairing screen says *Configuration found in iCloud: N servers* with their names and explains that the credentials arrive with the pairing code. The phone/Mac can now **send all servers at once** (Settings › Pair an Apple TV › *Send all servers*): the whole configuration lands on the TV in one go and the TV registers itself on each gateway. Older TVs keep working: the first server also travels in the legacy fields.
- **Video that does not start — the real reason.** Before mpv opens a file (Apple TV, iPhone, iPad, Mac) the app fetches its first byte with the same headers: a Cloudflare Access login page, a `401`, a revoked device or a gateway error are now reported as such instead of mpv's *unrecognized file format*. Streams use a **media ticket** (gateway 0.6+), so playback and seeking keep working after the session token expires; headers stay for Cloudflare Access.
- **Apple TV explorer:** *Rename* and *New folder* (on-screen keyboard), next to Copy, Cut, Paste, Delete (with confirmation) and Info.
- Apple TV registers with the name you gave it (Settings › General › About) so the gateway's Devices card tells the TVs apart.
- Build scripts: archives, intermediates and exports live outside the repository (`DD_ROOT`, default `~/Library/Caches/UnraidDrive-build`), because a checkout inside Google Drive gets extended attributes on the build products and CodeSign refuses them.

## 1.3 (build 29) — 2026-09-11

- **Device registration** (unraid-gateway 0.9+): each installation has a stable id; adding a server, editing its credentials or pairing an Apple TV registers the device on the gateway. When the admin removes the device there, the app is signed out with a clear message and only a new *Connect* (server → Edit server or credentials) registers it again; background logins never do. Older gateways ignore the extra fields.

- Every request tells the gateway which device and component is calling (`X-Unraid-Drive-Client`: app version, device family and OS, App / File Provider / Apple TV), so the gateway's new **Activity panel** (unraid-gateway 0.7+) can show who is connected and what is streaming. No identifiers beyond model family and OS version.

- **A real file explorer in the app, on every device.** *Browse shares* is now a Files-style explorer on iPhone, iPad, Vision Pro, Mac and Apple TV: list or icons, sort by name/kind/date/size, search in the folder, Info sheet (type, size, date, path, permissions), and on iPhone/iPad/Mac/Vision Pro the usual operations through the gateway with your Unraid permissions — new folder, upload from the Files picker, rename, **copy / cut / paste** between folders (the explorer's own clipboard, the gateway copies or moves on the NAS), move and copy with a folder picker, share/export a copy, delete (swipe or long press). On Apple TV: copy, cut, paste and delete from the long-press menu.
- **Opens far more files.** Quick Look for images, PDF, text, Office and Apple documents; **mpv** (libmpv + FFmpeg, LGPL, via MPVKit) for MKV, AVI, WebM, MPEG-TS, FLAC, OGG, Opus, WMA and the other formats AVFoundation cannot play, on iPhone, iPad, Mac and Apple TV; built-in readers for **EPUB** (text), **CBZ comics** and **ZIP** listings everywhere; on Apple TV also a text/NFO/Markdown/CSV viewer and a PDF page viewer (no PDFKit there).
- **Apple TV:** mpv now sends the same headers as the app (bearer token and Cloudflare Access service token), so it works behind Cloudflare Access too — this is what made MKV/AVI fail with "cannot play" on TVs whose gateway sits behind Access. Files the TV cannot open show their details and, when Infuse or VLC are installed, an *Open in Infuse / VLC* button (through the gateway's signed media link; behind Cloudflare Access the /media path must be excluded from the Access policy).
- Kit: `FileKind`, `ZipArchive` (stored + deflate) and `EPUBBook` shared by all apps, with unit tests.

## 1.2 (build 23; Apple TV build 25) — 2026-09-11

- **Apple TV plays everything.** Files AVFoundation cannot decode (MKV, AVI, WebM, MPEG-TS, FLAC, OGG, Opus, WMA, …) open in a built-in **mpv** player: libmpv and FFmpeg (LGPL build) through [MPVKit](https://github.com/mpvkit/MPVKit), the same engine as IINA and mpv, rendered with Metal and hardware decoding. Apple formats keep the system player; if it fails on a file, a button hands over to mpv. Play/pause and ±10 s with the Siri Remote. Streaming uses the gateway's new **media ticket** (unraid-gateway 0.6+): a signed, expiring URL for that file only, no credential in the URL.

- Apple TV: the buttons on the pairing screen (New code, Try the demo, Done) are readable again when focused — the system style painted both the focused button and its text in the app colour.

- **Choose which shares to show.** After connecting a server, in the walkthrough (a *Choose the shares to show* step lists every server), from Settings › *Shares to show* and from the server's details, tick the shares you want in the Files app, the Finder, Shortcuts and on Apple TV. The gateway still lists only what your Unraid user may see; this is a further filter, like the folder selection of Google Drive or OneDrive. Stored with the server, so it travels with the iCloud configuration and with the Apple TV pairing; hidden shares disappear from the Files/Finder location and come back when re-ticked. Apple TV has its own *Shares to show* per server.
- Activity log and error list keep the gateway's explanation of a "permission denied" (folder, owner, mode and the fix) next to the system message (needs unraid-gateway 0.5.5+).
- Walkthrough "What's new" updated. Right after an iCloud restore the shares list explains that the credentials are still arriving through iCloud Keychain and offers *Try again*.

All notable changes to Unraid Drive. The server side has its own changelog in [unraid-gateway](https://github.com/sidimam/unraid-gateway/wiki/Changelog).

## 1.1 (build 20) — 2026-09-11

- **Apple TV** (build 21, tvOS 17+): media browser and player through unraid-gateway with the user's permissions, dashboard, pairing by 6-digit code from iPhone/iPad/Mac (Settings › Pair an Apple TV; AES-GCM over iCloud Key-Value Storage), demo server.

- **Shortcuts and Siri** (App Intents): *Save clipboard to Unraid Drive*, *Upload file*, *Get file*, *List folder*, *Refresh Unraid Drive locations*, *Test connection*; phrases in 7 languages; visible in Spotlight.
- **Notifications**: when a gateway stops answering (and when it is back) and when a file could not be uploaded or downloaded by the Files app or the Finder. Managed from the system Settings; a *Notifications ›* row in the app opens them.
- **Walkthrough at every update**: features and what's new, iCloud step (restore the configuration found in iCloud, or turn sync on — one backup shared by iPhone, iPad, Vision Pro and Mac), notification permission. Every step can be skipped; iCloud stays available in Settings.
- **App colour**: titles, headers, toggles and the Mac menu bar panel follow the colour chosen for the icon (setting renamed from "Icon colour").
- **Mac**: Homebrew cask `sidimam/tap/unraid-drive` and notarized DMG on GitHub Releases; Finder location, menu bar panel, Offline files, Error list.
- Store texts: the requirement of unraid-gateway on the server stated up front.

## 1.0 (build 17) — 2026-09-09

- First release: iPhone, iPad, Apple Vision Pro and Mac (universal purchase).
- Files app / Finder integration through a File Provider extension backed by unraid-gateway: browse, open, save, move, rename, delete; on-demand download; resumable chunked uploads; change journal with stable ids (gateway 0.5+).
- Direct HTTPS or Cloudflare Access with a service token; per-user access with Unraid share permissions.
- Dashboard (array, shares, gateway container, notifications), connection test, demo server, iCloud configuration sync, 7 languages, System/Light/Dark theme, six icon colours, Home Screen quick actions, hourly background refresh.
- Mac: Finder sidebar location, menu bar panel (Home / Activity / Notifications, pause, Offline files, Error list, Launch at login, Show only in the menu bar).
