# Troubleshooting

## The container does not start

- **Docker tab shows it stopped right after Apply.** Click the icon → **Logs**. The first lines say what is wrong; the usual one is `UNRAID_URL is required` (empty field) or `UNRAID_URL must start with http:// or https://`.
- **`bind: address already in use`**: port 8484 is taken. Change the host side of *Gateway port* to e.g. 8485 and use that port everywhere.
- **`data root: ... not a directory`**: a mapped Host Path does not exist. Check the share names (`ls /mnt/user`).

## Invalid API key

The gateway page or the app says *invalid api key* although you pasted it correctly.

1. On Unraid open **Settings → Management Access → API Keys** and check the key still exists.
2. Check the container's **Unraid WebGUI URL**: it must be the LAN IP of Unraid with the scheme your WebGUI actually uses. Test from the Unraid terminal:
   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" -X POST http://192.168.0.100/graphql \
        -H "Content-Type: application/json" -d '{"query":"{ __typename }"}'
   ```
   `200` (or `400`) means reachable. A `301`/`302` means the WebGUI redirects to HTTPS: set the URL to `https://...` and, if the certificate is self-signed, `UNRAID_INSECURE_TLS=true`.
3. Check the Unraid API is running: `unraid-api status` on the terminal. Restart with `unraid-api restart` if needed.
4. Look at the container logs: a line `unraid validation error` with details points at the cause.

## "invalid unraid username or password"

The API key was fine but Unraid's Samba rejected the user: wrong password, or a user that does not exist. Check the user in the Unraid WebGUI (*Users*), reset its password there if needed, then *Edit server or credentials* in the app. Repeated failures lock your IP for 15 minutes like API-key failures.

## "this Unraid user has no access to any share mounted in the gateway"

The user exists but Unraid's share security grants nothing on the shares mapped into the container (private shares the user is not listed on, or only non-exported shares). Add the user to the share's read or write list in *Shares → share → SMB Security Settings*, or map a share the user may access.

## "the Unraid share configuration is not readable by the gateway"

The gateway runs with `USER_AUTH` on but `/etc/samba/smb-shares.conf` is not mounted at `/unraid-shares/smb-shares.conf`. Add the Path mapping in the container settings (the template has it) or set `USER_AUTH=off`.

## Too many failed attempts

You typed a wrong key 5 times: your IP is locked for 15 minutes (`LOGIN_LOCKOUT`). Wait, or restart the container to reset. If you are behind Cloudflare and `TRUST_PROXY` is `false`, *all* remote users share one IP (Cloudflare's), so one person's mistakes lock everybody: set `TRUST_PROXY=true`.

## The app connects at home but not on 5G

You used the LAN URL. Add the server again with the public hostname from Step 3, or edit the tunnel. Test the hostname in Safari on the phone with Wi‑Fi off: `https://unraidfile.example.com/healthz` must show `{"status":"ok"}`.

## "Unexpected response … not valid JSON … Unexpected character '<'" or "Cloudflare Access is blocking the request"

The gateway answered with a **web page** instead of data. Almost always this is Cloudflare Access showing its login page because the request carried no valid service token:

- the server was added in the app with **Connection: Direct** and Access was enabled afterwards → remove the server and add it again with **Connection: Cloudflare Access**, pasting `CF-Access-Client-Id` and `CF-Access-Client-Secret`;
- the Access policy for the token has action **Allow** → it must be **Service Auth** (Allow means an interactive login; Service Auth checks the token);
- the token expired or the policy's Service Token rule points to a different token.

Quick check from a terminal: without headers `curl -I https://gw.example.com/healthz` must return `302` to `…cloudflareaccess.com`; with the two `CF-Access-Client-*` headers it must return `200` and JSON.

## Files shows "Unraid Drive" but folders are empty or spinning

- Pull down to refresh.
- Open the Unraid Drive app once: it refreshes the session.
- Check the gateway is reachable from the device (Safari test above).
- On iOS, **Settings → Unraid Drive** → make sure *Cellular Data* is allowed.
- If it still spins, remove the server in the app and add it again; this rebuilds the local index.

## Changes made on the NAS take a while to appear

With gateway 0.5 or newer and app build 14 or newer, the gateway keeps an index of the shares and the app asks it for the changes since its last sync. Changes made through the app or the web UI are visible immediately; changes made over SMB or by other containers are picked up by the gateway's directory scan (every 5 minutes by default, `INDEX_DIR_SCAN`) and by the full scan (every 6 hours, `INDEX_FULL_SCAN`), or as soon as somebody opens that folder in the app. Opening the folder in Files always shows the current content.

## Files still shows the old icon next to the location

Files keeps the icon it saw when the location was registered. The app re-registers its locations once whenever its icon changes (build 15 and later); to force it, use **Rebuild the Files location** on the server page, or remove and re-add the server.

## Files says "Sync paused" (or a share you removed from the container is still listed)

iOS pauses a location after a network error, for example while the container restarts during an update, and then shows the cached listing until something wakes it up. Nothing is lost.

1. Open the Unraid Drive app: since build 7 it nudges every location whenever it comes to the foreground, and the server page has **Refresh the Files app**. **Test connection** does the same in its last check. Since build 8 the extension also re-reads the list of shares on every sync pass, so a share you unmapped from the container disappears from Files (together with anything cached below it) instead of producing endless "Error" retries. Since build 10 the app also rebuilds each location once per installation: after a reinstall (or a restore from iCloud) iOS keeps the old cached tree for the same server while the extension's own index is gone, so the two disagree and every share shows "Error ↑" with the location paused. The rebuild removes the location and registers it again. You can trigger it yourself from the server page with **Rebuild the Files location** (files created in Files but never uploaded are lost).

"Sync paused" at the bottom of a folder means that some item in this location cannot be uploaded, or that the gateway was unreachable the last time iOS tried; fix or delete that item (or rebuild the location) and the status goes back to "Synced".

A gateway that restarts every night (Unraid's *Appdata Backup* plugin stops and starts containers, *CA Auto Update* recreates them) makes the location pause each time iOS happens to sync during the restart. Since build 13 the app refreshes its locations in the background about once an hour, so they recover on their own. You can also exclude `unraid-gateway` from Appdata Backup: it has no appdata to back up.
2. In Files, pull down in the Unraid Drive folder.
3. Still paused? Toggle Airplane mode (or Wi-Fi) off and on: iOS re-checks paused locations when the network changes.
4. Last resort: in the app remove the server and add it again. The Files location is recreated from scratch.

The bottom of the shares list always says *Read only*: that is the list of shares itself, which you cannot rename or delete. Inside a share you can write normally.

## Files says "The operation couldn't be completed" when saving

- You are saving at the **root or share level**. Open a share and a folder inside it.
- The share is mapped **Read Only** in the container.
- The file name collides with an existing one; Files normally offers to replace, but some apps do not.
- Disk full on the NAS: the gateway returns *no space left on share*.

## Uploads of big files fail through Cloudflare from the gateway web page

Cloudflare limits a request to 100 MB. The **app** chunks uploads and is not affected; the gateway web page is. Use the app, or SMB on the LAN, for huge files.

## Dates look wrong

The gateway preserves the file modification time you send and reports the server's time. Make sure `TZ` in the container matches your timezone (display only; timestamps are UTC internally).

## Where are the logs

- Gateway: Docker tab → icon → **Logs**. One readable line per event: `TIME LEVEL  METHOD PATH → STATUS in Nms  file=… user=… ip=…`, plus explicit messages such as "login failed: Unraid rejected the username/password". The **Console** button opens a guided status check (`gw status`, `gw shares`, `gw login <user>`).
- iOS: **Settings → Privacy & Security → Analytics** does not include extension logs; when reporting an issue, describe the exact steps and attach the gateway log lines around that time.

## Reporting a bug

Open an issue on <https://github.com/sidimam/unraid-drive/issues> (app) or <https://github.com/sidimam/unraid-gateway/issues> (container) with: Unraid version, gateway version (`/healthz`), how you reach it (LAN / Cloudflare / other), and the relevant log lines. Never paste your API key or service token.
