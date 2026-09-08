# FAQ

**Do I need Unraid Connect or a myunraid.net account?**
No. The gateway talks to the Unraid API on your LAN; Unraid Connect is not involved.

**Does the API key's role limit what I can do with files?**
No. Roles only affect the dashboard (GraphQL). File access is decided by the container mounts. A `VIEWER` key uploads and deletes files just fine.

**Why not just use SMB from the Files app?**
Files can connect to SMB, but only on the LAN or over a VPN, and it does not integrate into the Locations list as a synced provider. Unraid Drive works from anywhere and behaves like iCloud Drive.

**Why a container? Can't the app talk to Unraid directly?**
Unraid's API has no file operations; and exposing SMB or SSH to the Internet is a bad idea. The gateway is a minimal, API-key-authenticated file service purpose-built for the Files app.

**Is my data going through the developer's servers?**
No. There are none. Data goes device ↔ Cloudflare (or your proxy) ↔ your NAS.

**Can I use it without Cloudflare?**
Yes, with any reverse proxy that gives a valid certificate, or over your VPN. See [Alternatives to Cloudflare](Alternatives-to-Cloudflare).

**Does it work on Apple Vision Pro?**
Yes, natively. The Files app on visionOS shows Unraid Drive like on iPad.

**Does it work on Mac?**
Not yet. A macOS version would need a separate File Provider build; it is on the roadmap.

**I restored my iPhone: do I have to set everything up again?**
Not if *Sync configuration with iCloud* was on (gear icon → Settings). The first launch offers *Restore from iCloud*: servers come back from iCloud Key-Value Storage and their secrets from iCloud Keychain. Without sync, add the server again with URL and key.

**Several Unraid servers?**
Add each one as a server in the app. Each appears as its own folder in the Files app.

**Several users in the family?**
One gateway, one API key (or one per device), and each person enters their own **Unraid username and password** in the app. The gateway applies Unraid's share security per user (public / secure / private, read and write lists), so everybody sees exactly what they see over SMB. Passwords are verified by Unraid's Samba, not stored by the gateway.

**What happens if the container is down?**
The Files app shows the last known listing and cached files; new operations wait and show a sync warning until it is back.

**Can I run the gateway on something other than Unraid?**
Technically yes (it is a normal Docker image) but it needs an Unraid API to validate keys, so it only makes sense next to an Unraid server.

**Is the code open?**
Yes: [unraid-gateway](https://github.com/sidimam/unraid-gateway) (Go) and [unraid-drive](https://github.com/sidimam/unraid-drive) (Swift), both MIT.
