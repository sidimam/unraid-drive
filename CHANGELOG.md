# Changelog

## 1.2 (build 22) — 2026-09-11

- **Choose which shares to show.** After connecting a server, in the walkthrough (a *Choose the shares to show* step lists every server), from Settings › *Shares to show* and from the server's details, tick the shares you want in the Files app, the Finder, Shortcuts and on Apple TV. The gateway still lists only what your Unraid user may see; this is a further filter, like the folder selection of Google Drive or OneDrive. Stored with the server, so it travels with the iCloud configuration and with the Apple TV pairing; hidden shares disappear from the Files/Finder location and come back when re-ticked. Apple TV has its own *Shares to show* per server.
- Activity log and error list keep the gateway's explanation of a "permission denied" (folder, owner, mode and the fix) next to the system message (needs unraid-gateway 0.5.5+).
- Walkthrough "What's new" updated.

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
