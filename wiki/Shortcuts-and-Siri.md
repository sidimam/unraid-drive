# Shortcuts and Siri

Unraid Drive 1.0 (build 18) exposes its actions to the **Shortcuts** app and to **Siri** on iPhone, iPad, Apple Vision Pro and Mac. They also show up in Spotlight.

| Action | What it does | Parameters |
|---|---|---|
| **Save clipboard to Unraid Drive** | Saves the clipboard as a new file: text → `.txt`, image → `.png`, a copied file as is (Mac), a link → `.url.txt` | Server, Folder (`share/folder`), File name (`{date}` = current date and time) |
| **Upload file to Unraid Drive** | Uploads a file coming from the previous action (photo, PDF, document…) | File, Server, Folder, Replace if it exists |
| **Get file from Unraid Drive** | Downloads a file and passes it on (share it, open it, attach it…) | Server, Path (`share/path/file`) |
| **List folder on Unraid Drive** | Returns the names in a folder (folders end with `/`); empty folder = the shares | Server, Folder |
| **Refresh Unraid Drive locations** | Asks the Files app / Finder to re-read every location from the gateway | — |
| **Test Unraid Drive connection** | Gateway reachable and key accepted, spoken/shown as a sentence | Server |

Siri phrases (in every app language), e.g. *"Save the clipboard to Unraid Drive"*, *"Refresh Unraid Drive"*, *"Is Unraid Drive reachable"*.

## Examples

- **Notes → NAS**: in Notes share a note as text or PDF to Shortcuts, then *Upload file to Unraid Drive* into `documents/Notes`.
- **Clipboard to NAS**: copy anything, say *"Save the clipboard to Unraid Drive"*; the file lands in the folder you chose the first time.
- **Automation**: when you arrive home (Personal Automation), run *Refresh Unraid Drive locations* so the Files app is already up to date.
- **Backup a photo**: Photos › Share › your shortcut with *Upload file to Unraid Drive* into `media/Photos`.

## Notes

- The actions use the server's API key stored in the Keychain of the device; if it is missing (typical on a new Mac without iCloud Keychain) the action says so — open the app and enter it.
- Paths are `share/folder`; the leading slash is optional. Uploads that would overwrite an existing file fail unless *Replace if it exists* is on.
- Reading the clipboard from a shortcut may show the system paste confirmation on iOS.
