# Step 2 — Create an Unraid API key

The API key is what the app uses to prove it is you. It is **not** your Unraid password and it is **not** configured in the container: you type it in the app (and, optionally, in the gateway web page to test). Create one key per device or one key for all your devices, as you prefer; keys can be revoked at any time.

## 2.1 In the Unraid web interface

1. Click **Settings**.
2. Under *Management Access* click **API Keys** (on Unraid 7.2/7.3 it is a dedicated page; on older 7.x it is inside *Management Access*).
3. Click **Add API Key** (or **Create**).
4. Fill in:
   - **Name**: `Unraid Drive iPhone` — letters, digits and spaces only. Hyphens and other symbols are rejected.
   - **Description**: anything, e.g. `Files app on my phone`.
   - **Roles**: tick **VIEWER**.
     - `VIEWER` is enough for **everything the app does today**: browsing, uploading, downloading, renaming and deleting files, and the read-only dashboard.
     - Choose `ADMIN` only if you plan to use the gateway's GraphQL proxy for actions that change the server (future versions may add container start/stop). More rights than needed is more risk than needed.
   - **Permissions**: leave empty; the role covers it.
5. Click **Create**.
6. The key is shown **once**. It is a long string of letters and digits. Copy it now:
   - on the same device you will use for the app, copy it to the clipboard and paste it into the app in Step 5;
   - otherwise store it in a password manager (1Password, Bitwarden, iCloud Keychain notes). Never send it by e‑mail or chat in clear text.

If you lose it, simply delete the key and create a new one.

## 2.2 Test the key against the gateway (recommended)

1. Open the gateway web page: **Docker** tab → *unraid-gateway* icon → **WebUI**, or go to `http://<server-ip>:8484/`.
2. Paste the key in the field and click **Connect**.
3. You should see your shares listed, your key name and role in the top-right corner, and be able to open a share, upload a small file and delete it again.
4. Click **Disconnect** when done. The page keeps nothing.

If the page says *invalid api key*, see [Troubleshooting](Troubleshooting#invalid-api-key).

## 2.3 Command-line alternative

On the Unraid terminal:

```bash
unraid-api apikey --create --name "Unraid Drive iPhone" --roles VIEWER --json
```

The JSON output contains `"key": "..."`. Same rules apply: the name allows letters, digits and spaces only.

## 2.4 Revoking a key

**Settings → Management Access → API Keys**, click the bin icon next to the key. The app will show *invalid or expired session* on its next request; remove and re-add the server with a new key.

→ Next: [Step 3 — Publish the gateway with Cloudflare Tunnel](Step-3-Publish-with-Cloudflare-Tunnel)
