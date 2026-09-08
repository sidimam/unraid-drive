# Step 3 — Publish the gateway on the Internet with Cloudflare Tunnel

At home, the app can already reach `http://<server-ip>:8484`. To use it on 5G or from anywhere you need a **public HTTPS address** for the gateway. Cloudflare Tunnel is the recommended way because:

- **no port forwarding** on your router and it works behind CGNAT (most fibre and all 5G connections in Europe);
- **free** for personal use;
- a **valid TLS certificate** is provided automatically, which iOS requires for File Provider extensions;
- optional extra protection with [Cloudflare Access](Step-4-Protect-with-Cloudflare-Access).

You need a Cloudflare account and a domain whose DNS is on Cloudflare. Any cheap domain works.

## 3.1 Create the tunnel (skip if you already have one)

1. Go to <https://one.dash.cloudflare.com> and log in.
2. In the left menu: **Networks → Tunnels** (on some accounts *Networks → Tunnels & Mesh*).
3. Click **Create a tunnel** → **Cloudflared** → **Next**.
4. Name it, e.g. `Home Tunnels`. Click **Save tunnel**.
5. On the *Install and run a connector* page, select **Docker**. Cloudflare shows a command like
   ```
   docker run cloudflare/cloudflared:latest tunnel --no-autoupdate run --token eyJhIjo...
   ```
   Copy **only the token** (the long string after `--token`).
6. On Unraid, install the **Cloudflared** container from Community Applications (search *cloudflared*, several templates exist; the *Cloudflared* by *ich777* or the official one both work). In the template, paste the token in the **Tunnel Token** field and click **Apply**.
7. Back in the Cloudflare page, the connector appears as **Connected** within a minute. Click **Next**.

## 3.2 Publish the gateway as a public hostname

1. Open your tunnel: **Networks → Tunnels → Home Tunnels** → **Public Hostname** tab (or *Published application routes*) → **Add a public hostname**.
2. Fill in:
   - **Subdomain**: `unraidfile` (anything you like)
   - **Domain**: pick your domain, e.g. `example.com`
   - **Path**: leave empty
   - **Service → Type**: `HTTP`
   - **Service → URL**: `192.168.0.100:8484` — your Unraid LAN IP and the gateway port. Use the IP, not `localhost`, unless the Cloudflared container runs in *host* network mode.
3. Click **Save hostname** (or **Save**). Cloudflare creates the DNS record automatically.

## 3.3 Test it

From any device, also on mobile data:

```
https://unraidfile.example.com/healthz
```

must show `{"status":"ok","version":"..."}`. Opening `https://unraidfile.example.com/` shows the gateway page with the login card. If it does, your gateway is reachable from the Internet with a valid certificate. **This is the URL you enter in the app.**

## 3.4 Two settings on the gateway

Both are already the default in the Unraid template; check them in the container settings (*Show more settings…*):

- `TRUST_PROXY = true` — Cloudflare puts the real client address in a header; with this on, brute-force lockouts hit the attacker, not Cloudflare.
- `SESSION_TTL` — leave `12h`.

## 3.5 Things to know about Cloudflare

- **Upload size**: Cloudflare limits a single HTTP request body to **100 MB** on free and Pro plans. The app splits uploads into 8 MB chunks, so files of any size work from the app and from the Files app. The gateway *web page* uploads in one request, so it is limited to 100 MB per file.
- **Bandwidth**: Cloudflare's free plan is meant for web sites. Streaming a 4K movie library through it is against the spirit of their terms; syncing documents, photos and downloads is fine.
- **Privacy**: Cloudflare terminates TLS, so technically it can see traffic in transit, like any reverse proxy service. Files are not stored there. If that is not acceptable to you, see [Alternatives to Cloudflare](Alternatives-to-Cloudflare).

→ Next: [Step 4 (optional) — Protect it with Cloudflare Access](Step-4-Protect-with-Cloudflare-Access) or jump to [Step 5 — Add the server in the app](Step-5-Add-the-server-in-the-app).
