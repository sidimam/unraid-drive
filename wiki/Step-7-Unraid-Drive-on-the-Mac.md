# Step 7 — Unraid Drive on the Mac

The same app runs on macOS 14 or later (Universal Purchase: one App Store download for iPhone, iPad, Vision Pro and Mac). On the Mac it behaves like the other cloud drives: your servers are **locations in the Finder sidebar** and a **menu bar panel** shows what is going on.

## First launch

1. Install Unraid Drive: from the **Mac App Store** (universal purchase), with **Homebrew** (`brew install --cask sidimam/tap/unraid-drive`) or from the **DMG** on the [GitHub Releases](https://github.com/sidimam/unraid-drive/releases/latest) page (Developer ID signed and notarized; drag the app into Applications). Then open it.
2. Add your server as on iOS (**+** → gateway URL, API key, optional Unraid login and Cloudflare Access token). If you enabled iCloud sync on the iPhone, the server list arrives by itself; the secrets arrive through **iCloud Keychain** — if that is off on the Mac, the app asks for the API key again (the Finder shows *"has not signed in"* with a **Sign in…** button until you do).
3. macOS asks you once to allow the extension: **System Settings › General › Login Items & Extensions › File Providers → Unraid Drive**. The menu bar panel and the server page show a banner with a button that opens the right pane until it is enabled.
4. Open the Finder: under **Locations** you find *Unraid Drive – ‹server name›* with the shares inside. Files download when you open them (cloud badge = on the NAS only).

The location lives in `~/Library/CloudStorage/UnraidDrive-‹server›`, so any Mac app and the Terminal can use the files.

## Menu bar panel

Click the Unraid Drive glyph in the menu bar:

- **Home** — *Open ‹server› folder* buttons, the sync status (Up to date / Paused / Disabled in System Settings / Credentials missing / Disconnected), the last activity.
- **Activity** — every download, upload, new folder, rename and deletion the extension performed, with size and time; failures are red. *Clear* empties the list.
- **Notifications** — unread Unraid notifications (alerts and warnings) of each server.
- **⏸ / ▶** pauses and resumes all locations (the Finder greys them out while paused).
- **⚙ gear** — Preferences (the main window), Offline files (space used on this Mac per server, *Free up space*), Error list, About, Help, Send feedback, **Launch at login**, **Show only in the menu bar**, **Theme** (System / Light / Dark), **App colour**, Quit.
- **Refresh** (bottom right) asks the Finder to re-read every location from the gateway and reloads status, activity and notifications; it shows the time of the last check.

*Show only in the menu bar* turns Unraid Drive into a menu-bar app: no Dock icon, the panel is the entry point and *Open Unraid Drive* brings the window back. Theme, language and icon colour are the same settings as on iOS (Preferences › App settings); on the Mac the icon colour applies to the Dock icon while the app runs.

The Finder location lists only the shares ticked under the server page › **Shares to show** (Preferences… from the menu bar panel opens the app). Hiding a share removes it from the sidebar folder; ticking it again brings it back.

## Everyday operations

| You want to… | Do this |
|---|---|
| Open a file | double-click. It downloads first (cloud badge), then opens |
| Copy files to the NAS | drag them into the share folder; the upload starts at once (Activity shows it) |
| Keep a file offline | right-click → **Download Now**; the system may evict rarely used copies when space runs low |
| Free space on the Mac | right-click → **Remove Download**, or **Offline files… → Free up space** in the menu bar panel |
| Rename, move, delete | as with any folder; the change goes to the NAS and appears on the other devices within minutes |

## Troubleshooting on the Mac

- **"Unraid Drive – ‹server› has not signed in"** with a **Sign in…** button: the Mac has no API key for that server. Click the button (or open the app): the credentials sheet appears; enter the key (and Unraid login) and the Finder resumes.
- **The location is greyed out / "Disabled in System Settings"**: enable *Unraid Drive* under System Settings › General › Login Items & Extensions › File Providers.
- **Sidebar shows a plain folder icon**: the Finder caches the icon; restart the Finder (⌥-right-click its Dock icon → Relaunch) or log out and in.
- **Nothing syncs**: check the panel is not paused (▶ button), then *Refresh*; the Error list shows what failed and why.
