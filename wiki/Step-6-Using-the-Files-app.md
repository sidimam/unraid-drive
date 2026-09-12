# Step 6 — Use your shares in the Files app

## Finding your shares

1. Open the **Files** app.
2. Tap **Browse** (bottom right on iPhone; sidebar on iPad).
3. Under **Locations** you see **Unraid Drive**. The first time, iOS asks *Do you want to enable "Unraid Drive"?* → **Enable**. (If it does not appear, tap **⋯ → Edit** at the top of the Browse page and switch it on.)
4. Tap it. Each server you added is a folder; inside, each mapped share is a folder.

On iPad and Vision Pro you can also drag **Unraid Drive** into the sidebar favourites.

If a share you expect is missing, check the server page › **Shares to show** in the app: hidden shares are simply not listed here (see [Step 5.9](Step-5-Add-the-server-in-the-app#59-choose-which-shares-to-show)).

## Everyday operations

| You want to… | Do this |
|---|---|
| Open a file | tap it. It downloads on first open (cloud icon), then opens in the built-in viewer or in the app you choose |
| Save a file from another app to Unraid | in that app use **Share → Save to Files** (or *Export*), navigate to *Unraid Drive → server → share*, **Save** |
| Upload photos | Photos app → select → **Share → Save to Files** → pick a share |
| Copy or move | long-press → **Copy** / **Move**, or drag and drop between locations on iPad |
| Rename, duplicate, delete | long-press the item |
| New folder | **⋯** menu (iPhone) or the *new folder* button (iPad) inside a share |
| Attach a NAS file in Mail | Mail → attachment → **Browse** → Unraid Drive |
| Open a NAS document in Pages, GoodNotes, etc. | in that app choose *Open… / Browse* → Unraid Drive |
| Free space on the device | long-press → **Remove Download**. The file stays on the NAS |
| Keep a file available offline | long-press → **Download Now** (iOS 17+) |

## What the little icons mean

- **cloud with arrow**: on the NAS, not downloaded yet. Tap to fetch.
- **progress ring**: transfer in progress. Large uploads are sent in chunks and resume after a network drop.
- **exclamation**: the last sync failed. Usually the gateway is unreachable; see [Troubleshooting](Troubleshooting).

## How changes made elsewhere show up

If you add files on the NAS via SMB or another device, the Files app picks them up when you open or pull-refresh the folder, and periodically in the background through the gateway's change feed. On very large shares (hundreds of thousands of files) the first full sync of a folder tree can take a minute; subsequent checks are incremental.

## The explorer inside the app

*Browse shares* on the server page is a Files-style explorer of the same tree: list or icons (menu at the top right), sort by name, kind, date or size, search in the folder, an **Info** sheet per item (type, size, date, path, your permissions on that share). Long-press (or right-click on the Mac) for **Open** (the right viewer for the file: mpv for MKV/AVI…, the EPUB/comic/archive readers, Quick Look for the rest), **Quick Look**, **Share…**, **Download…**, **Info**, **Select**, **Copy**, **Cut**, **Rename**, **Move…**, **Copy to…** and **Delete**; **Select** (toolbar) turns on multi-selection: tick files and folders (*Select all*, ⌘/⇧-click on the Mac) and use the bar at the bottom — Copy, Cut, Move…, Copy to…, Download, Share…, Delete — on the whole selection, one confirmation for the lot; *Move…* and *Copy to…* confirm the destination with a *Move here* / *Copy here* button; *Download* fetches the items (folders recursively) and asks where to save them; the **+** menu creates a folder, uploads files from the Files picker and offers **Paste** when something was copied or cut (the gateway copies or moves on the NAS, nothing is downloaded; a folder's long-press menu also has *Paste into folder*). Everything goes through the gateway with your Unraid permissions; shares marked read-only offer no editing. Quick Look shows images, PDF, text, Office and Apple documents; MKV, AVI, WebM, FLAC and the other formats AVFoundation cannot play open in the built-in **mpv** player (libmpv + FFmpeg, LGPL); EPUB books, CBZ comics and ZIP archives have readers of their own. On Apple Vision Pro the mpv player is not available: use Quick Look or the Files app there.

## Limits and good practice

- **Root and share level are read-only.** You cannot create files directly under *Unraid Drive → server*; open a share first. You also cannot rename or delete a share from Files: shares are mount points managed in the container settings.
- **Very large files** work (there is no size limit in the app), but remember Cloudflare's 100 MB single-request limit applies only to the gateway *web page*, not to the app, which chunks uploads.
- **Do not point the Photos app "Sync" or third-party backup tools at a share** through the Files app; they are not designed for cloud providers and will spin. Use Immich or a dedicated backup app for that.
- **Battery**: like every cloud provider, syncing happens when you use Files or when iOS schedules background refresh. Nothing runs continuously.

→ See also: [Troubleshooting](Troubleshooting), [Security notes](Security)
