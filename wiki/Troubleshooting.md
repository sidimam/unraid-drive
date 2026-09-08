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

## Too many failed attempts

You typed a wrong key 5 times: your IP is locked for 15 minutes (`LOGIN_LOCKOUT`). Wait, or restart the container to reset. If you are behind Cloudflare and `TRUST_PROXY` is `false`, *all* remote users share one IP (Cloudflare's), so one person's mistakes lock everybody: set `TRUST_PROXY=true`.

## The app connects at home but not on 5G

You used the LAN URL. Add the server again with the public hostname from Step 3, or edit the tunnel. Test the hostname in Safari on the phone with Wi‑Fi off: `https://unraidfile.example.com/healthz` must show `{"status":"ok"}`.

## Files shows "Unraid Drive" but folders are empty or spinning

- Pull down to refresh.
- Open the Unraid Drive app once: it refreshes the session.
- Check the gateway is reachable from the device (Safari test above).
- On iOS, **Settings → Unraid Drive** → make sure *Cellular Data* is allowed.
- If it still spins, remove the server in the app and add it again; this rebuilds the local index.

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

- Gateway: Docker tab → icon → **Logs**. Every request is one JSON line with method, path, status, duration and client IP.
- iOS: **Settings → Privacy & Security → Analytics** does not include extension logs; when reporting an issue, describe the exact steps and attach the gateway log lines around that time.

## Reporting a bug

Open an issue on <https://github.com/sidimam/unraid-drive/issues> (app) or <https://github.com/sidimam/unraid-gateway/issues> (container) with: Unraid version, gateway version (`/healthz`), how you reach it (LAN / Cloudflare / other), and the relevant log lines. Never paste your API key or service token.
