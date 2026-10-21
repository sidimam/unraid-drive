# Sync and backup (1.5)

Unraid Drive 1.5 can keep folders aligned with Unraid and back your photos up, through the gateway, with the gateway keeping the registry of what every device syncs.

## Where
*Settings › Profiles › your server › Sync*. One row per pair: what it syncs, the arrow (device → Unraid, Unraid → device, two-way), the Unraid folder, the last run and its outcome, a switch to pause it, **Run now**. Tap a row for the **recent files** (what moved, conflicts, failures). On the Mac the menu bar panel shows every pair with live progress.

## Kinds
- **Folder sync (Mac)** — a folder of the Mac ↔ a folder of Unraid. Options: direction; what to do when a file changed on both sides (*newest wins*, *keep both* — your copy becomes `name (Mac).ext` on both sides and the Unraid copy keeps the original name —, *keep the existing copy*, *ask*: the conflict is recorded and nothing is touched); deleted files (*keep them on the other side* or *delete on the other side too*; local deletions go to the Trash); exclusion patterns (`*.tmp, node_modules`; `.DS_Store`, `._*` and partial downloads are always excluded; bundles are synced as a whole, symlinks skipped); schedule (*continuous*: the folder is watched with FSEvents and a pass also runs every 15 minutes; hourly; daily; manual).
- **Photos backup (Mac, iPhone, iPad, Vision Pro)** — originals of photos and videos (RAW, HEIC, both halves of a Live Photo), incremental by asset and modification date, into `<folder>/<year>/<year-month>/<original name>`, plus `albums.json` (album → file names). iCloud-optimised originals are fetched on demand. Nothing is ever deleted on Unraid. Up to 400 assets per run; the next run continues.
- **Downloads sync (iPhone, iPad, Vision Pro)** — pick the Downloads folder of the device (or any folder) once; files that appear there are sent to Unraid (device → Unraid).

## How it runs
- Mac: in the background while the app is running (menu bar), with the watched folders and the 15-minute pass.
- iPhone, iPad, Vision Pro: while the app is open and, when the system allows it, as a background processing task (on power and, if you chose *Only on Wi-Fi*, on Wi-Fi). Opening the app runs what is due.
- Every run is reported to the gateway with the files that moved; failed or partial runs raise an app notification and colour the health dot (*Open Sync* leads to the pair).

## The gateway side (unraid-gateway 0.14)
Every pair is registered on the gateway (kind, local label, Unraid folder, direction). The web UI › Settings › **Users** view lists, per Unraid user, the devices and their pairs, with the files each one moved and the data moved over time. The administrator can **pause a pair on the gateway**: the app sees it at the next run, shows *Paused on the gateway (by …)* and cannot resume it from the app; resume it in the web UI or with `gw syncs resume <id>`. Removing a device from the gateway removes its pairs.

## Share extension
*Save to Unraid Drive* appears in the share sheet of every app (iPhone, iPad, Vision Pro, Mac): files, images, movies, text and links. Pick the profile and the folder (the last destination is preselected, recent ones are listed, a new folder can be created on the spot). Text is saved as `.txt` (`.md` when it starts with `#`), a link as `.webloc` or, with *Download what the link points to*, as the file itself.

## Continuity
Handoff: the folder you are browsing appears on your other devices (Dock on the Mac, app switcher on iPhone/iPad). *Settings › iCloud › Open where I left off on another device* opens, at launch, the folder another device opened in the last hour.
