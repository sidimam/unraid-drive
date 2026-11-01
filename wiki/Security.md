# Security notes

## Threat model in one paragraph

The only thing exposed to the Internet is the gateway (through Cloudflare or your reverse proxy). Everything it can do is bounded by two things you control: **which shares are mounted** into the container, and **a valid Unraid API key**. The Unraid web interface, SSH and SMB are never exposed.

## What protects you

- **API key required for everything.** No endpoint except `/healthz` and the login answers without a key or session token. The key is validated by Unraid itself.
- **Brute-force protection.** 5 failed logins lock the client IP for 15 minutes.
- **Sessions are short-lived and in memory.** A restart of the container invalidates all of them.
- **Path confinement.** Every path is resolved inside `/data`; `..` and symlinks escaping the root are rejected. Shares (mount points) cannot be renamed, moved, replaced or deleted through the API, and nothing can be created at root level.
- **Unprivileged container.** It runs as `nobody:users` (99:100), so files it creates have the same ownership as files created over SMB, and it cannot touch anything not mounted.
- **TLS end to end.** Cloudflare (or your proxy) terminates HTTPS; between Cloudflare and your NAS the tunnel is encrypted. Inside your LAN the hop from cloudflared to the gateway is plain HTTP on the same host.
- **Optional Cloudflare Access.** With a service token, requests without the token never even reach your home.
- **Credentials in the profile (1.5.3+).** The API key, the Cloudflare token and the optional Unraid login are part of the server profile, stored in the app's own container (app group) shared only with its extensions, and — with iCloud sync on — in your own iCloud Key-Value Storage, encrypted by Apple (end-to-end with Advanced Data Protection), so any device of yours and any reinstall gets them. They never go into the readable `servers.json`, the diagnostics or the log. Only the gateway session cache stays in the Keychain, this device only.

## Per-user access

With an Unraid username and password in the app, the gateway opens a real SMB2 session to Unraid to verify them (Samba is the authority; the gateway keeps only the resulting permission map for the session) and enforces Unraid's per-share security on every request. Without a user, access is whatever the container mounts allow; `USER_AUTH=required` on the gateway removes that option.

## Good practice

1. Use a **VIEWER** key unless you need more.
2. One key **per device**, named after it; revoke it if the device is lost.
3. Map **only the shares you need**; mark libraries **Read Only**.
4. Never map `appdata`, `system`, `domains`, `isos` or Time Machine shares.
5. Keep the container on `latest` and let Unraid update it.
6. Enable **Cloudflare Access** if you want an additional gate.
7. Do not expose the Unraid WebGUI, SSH or SMB to the Internet to "make it easier".

## What the app does *not* collect

Nothing. There is no analytics, no crash reporting service, no account, no server operated by the developer. The app talks only to the URL you enter.
