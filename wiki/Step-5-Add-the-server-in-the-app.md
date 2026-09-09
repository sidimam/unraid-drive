# Step 5 — Add the server in the app

## 5.1 First launch

1. Open **Unraid Drive**. A short welcome walkthrough explains the four steps; swipe through it or tap **Skip**. You can reopen it any time with the **?** button.
2. You land on the server list, empty for now, with two buttons: **Add server** and **Try the demo**.

**Try the demo** adds a sample server with a few folders and files that live only on your device. It also appears in the Files app, so you can see exactly how the integration behaves before touching your NAS. Swipe left on it to remove it later.

## 5.2 Add your server

1. Tap **+** (or **Add server**).
2. **Name**: anything, e.g. `Home NAS`. This is the name shown in the Files app.
3. **Gateway URL**:
   - from outside your home: the public hostname from Step 3, e.g. `https://unraidfile.example.com`
   - LAN only: `http://192.168.0.100:8484` — works only on your Wi‑Fi; **do not** use it if you want the shares on 5G.
   If you type without `https://`, the app adds it.
4. **Unraid API key**: paste the key from Step 2.
5. **Unraid user (optional)**: your Unraid username (e.g. `sdimambro`) and its password. The gateway checks them against Unraid's SMB service and then applies *your* share permissions: you only see the shares you may read, and read-only shares cannot be modified. Every family member can add the same gateway with their own user and see only their shares. Leave empty to use the container mounts as they are (unless the gateway is set to *required*).
6. **Connection**:
   - **Direct** — the normal case (LAN, reverse proxy, or Cloudflare Tunnel *without* Access).
   - **Cloudflare Access** — if you did Step 4. Two extra fields appear: paste `CF-Access-Client-Id` and `CF-Access-Client-Secret`.
7. Tap **Connect**. The app logs in to the gateway, which validates the key with Unraid. On success you briefly see *Connected* with your key name and role, and the sheet closes.

If it fails, the error is shown in red under the fields. The common ones:

| Message | Meaning | Fix |
|---|---|---|
| *The API key, or the Unraid username and password, were rejected* | key wrong or deleted; or wrong Unraid password | copy the key again; check the Unraid user's password (Users page in the WebGUI) |
| *This gateway requires an Unraid username and password* | the gateway runs with `USER_AUTH=required` | fill in the Unraid user section |
| *Cannot reach the gateway* | wrong URL, container stopped, tunnel down, or you are on LAN with an `https` URL that only resolves outside | open the URL in Safari on the same device first |
| *Too many failed attempts* | the gateway locked your IP after 5 wrong keys | wait 15 minutes |
| *Server error 403* on Cloudflare Access | wrong service token or the Access policy does not include it | redo Step 4.3 |
| The certificate is refused | self-signed HTTPS | iOS extensions require a real certificate: use Cloudflare or Let's Encrypt |

## 5.3 The server page

Tap the server to open its page:

- **Open in Files** jumps to the Files app.
- **Browse shares** is a quick built-in browser with preview.
- **System / Array / Shares / Docker** is a read-only dashboard fed by the Unraid API: hostname and version, CPU and memory load, unread notifications, array state and usage, parity check progress, disk temperatures, share usage, container states and update badges. Pull down to refresh.

## 5.4 Several servers

Repeat 5.2 for every Unraid server you have. Each one becomes its own location in the Files app.

## 5.5 Appearance and language

The gear icon on the server list opens **Settings**. The *Appearance* section has a **System / Light / Dark** theme switch and a **Language** picker. The app ships in English, Italian, Spanish, French, German, Simplified Chinese and Arabic; with *System* (the default) it follows the language of your iPhone, exactly like the installer does. Forcing a language changes the interface immediately; a few texts provided by iOS itself (error messages from the network stack, formatters) switch at the next launch.

The same section has the **App icon** colour dots (Unraid orange, red, blue, teal, purple, graphite). The icon is a Files-style folder holding the three Unraid bars, on purpose different from the unraid-gateway container icon, and it follows the iOS light, dark and tinted Home Screen styles. Interface accents, headers and titles use the Unraid orange from unraid.net.

## 5.6 Keep the configuration after a restore (iCloud sync)

Tap the gear icon on the server list → **Sync configuration with iCloud**. When on:

- the server list (names, URLs, connection modes) is stored in your iCloud account (Key-Value Storage);
- API keys and Cloudflare service tokens are stored in **iCloud Keychain**, end-to-end encrypted by Apple;
- after restoring, replacing or adding an iPhone/iPad/Vision Pro signed in to the same iCloud account, the app shows **Restore N server(s) from iCloud** on its first launch; one tap brings everything back, Files app locations included.

When off (the default), nothing leaves the device. Turning it off again deletes the copy in iCloud. The demo server is never synced. Requires iCloud Drive and iCloud Keychain enabled in iOS Settings for your Apple ID.

## 5.7 Test the connection

Server page → **Test connection** runs five checks with a suggestion for whatever fails: gateway reachable (version, latency), API key accepted (identity, role), shares listed, write access (creates and removes a tiny temporary folder), Files app location registered. Use **Edit server or credentials** to fix URL, mode, key or token without deleting the server.

## 5.8 Removing a server

Swipe left on it in the list → **Delete**. This removes the Files app location, the cached files and the key from the Keychain. Nothing changes on the NAS.

→ Next: [Step 6 — Use your shares in the Files app](Step-6-Using-the-Files-app)
