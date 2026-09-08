# Step 1 — Install the gateway container on Unraid

The gateway is a single container, about 10 MB, with no database and no external dependencies. Until it is listed in Community Applications you install it from its template URL. Every click is listed below.

## 1.1 Add the template repository

1. Open the Unraid web interface in your browser, for example `http://192.168.0.100`.
2. Click the **Docker** tab.
3. Scroll to the bottom and click **Add Container**.
4. At the top of the page there is a **Template repositories** link (or a *Template* dropdown with *Template repositories* at the end). Click it.
5. In the text box paste, on its own line:
   ```
   https://raw.githubusercontent.com/sidimam/unraid-gateway/main/templates/unraid-gateway.xml
   ```
6. Click **Save**.
7. Back in **Add Container**, open the **Template** dropdown: you now see **unraid-gateway** under *User templates*. Select it. The form fills itself.

## 1.2 Fill in the form

Leave everything at its default except what follows.

| Field | What to enter | Why |
|---|---|---|
| **Repository** | `ghcr.io/sidimam/unraid-gateway:latest` | already filled; `latest` lets Unraid show updates |
| **Network Type** | `Bridge` | default |
| **Gateway port** | `8484` | change only if 8484 is already used on your server |
| **Unraid WebGUI URL** | `http://192.168.0.100` (your server's LAN IP) | the container uses it to validate API keys. Use the **IP**, not `localhost`, and `http://` unless you forced HTTPS on the WebGUI |
| **documents share** | `/mnt/user/documents` | rename or remove according to your shares |
| **media share** | `/mnt/user/media` | idem |
| **downloads share** | `/mnt/user/downloads` | idem |

### Mapping your own shares

Each share you want to see on your device is one **Path** entry:

- **Container Path**: `/data/<name>` — `<name>` becomes the folder name in the Files app. Letters, digits, `-` and `_` only.
- **Host Path**: `/mnt/user/<share>` — the real share.
- **Access Mode**: `Read/Write`, or `Read Only` for shares you only want to browse (media libraries, backups).

To add one: click **Add another Path, Port, Variable, Label or Device**, choose *Config Type: Path*, fill the three fields, click **Add**. Repeat as needed. To remove a preconfigured one, click **Remove** next to it.

> **Do not map Time Machine, `appdata`, `system`, `domains` or `isos`.** They contain sparsebundles, databases and disk images that iOS cannot use and that are easy to corrupt from a file browser.

### Advanced settings (Show more settings…)

You do not need to touch these to get started.

| Variable | Default | Meaning |
|---|---|---|
| `READ_ONLY` | `false` | `true` makes *every* share read-only regardless of the mount |
| `SESSION_TTL` | `12h` | how long a login stays valid; the app re-logs in silently |
| `MAX_LOGIN_ATTEMPTS` / `LOGIN_LOCKOUT` | `5` / `15m` | brute-force protection per IP |
| `TRUST_PROXY` | `true` | keep `true` when behind Cloudflare or a reverse proxy, so lockouts apply to the real client IP |
| `UNRAID_INSECURE_TLS` | `false` | only if your WebGUI URL is `https://` with a self-signed certificate |
| `CHANGES_DEADLINE` | `20s` | how long one sync scan may take on very large shares |
| `TZ` | `Europe/Rome` | log timestamps |

## 1.3 Start it

1. Click **Apply**. Unraid pulls the image (a few seconds) and starts the container.
2. Back on the **Docker** tab you see **unraid-gateway** with a green *started* dot and the orange gateway icon.
3. Click the icon → **WebUI**. A page titled *unraid-gateway* opens at `http://<server-ip>:8484/`. If you see the login card, the container is running. You will use this page in Step 2 to test your API key.

## 1.4 Updates

Because the template uses the `latest` tag, Unraid's **Check for Updates** button on the Docker tab shows when a new version is available, and **Update** applies it. If you use the *CA Auto Update Applications* plugin, you can add `unraid-gateway` to its list.

## Command-line alternative

If you prefer the shell (Unraid terminal or SSH):

```bash
docker run -d --name unraid-gateway --restart unless-stopped \
  -p 8484:8484 \
  -e UNRAID_URL=http://192.168.0.100 -e TRUST_PROXY=true -e TZ=Europe/Rome \
  -v /mnt/user/documents:/data/documents \
  -v /mnt/user/media:/data/media \
  -v /mnt/user/downloads:/data/downloads \
  ghcr.io/sidimam/unraid-gateway:latest
```

Then `curl http://127.0.0.1:8484/healthz` must answer `{"status":"ok",...}`.

→ Next: [Step 2 — Create an Unraid API key](Step-2-Create-an-API-key)
