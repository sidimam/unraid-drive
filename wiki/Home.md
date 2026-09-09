# Unraid Drive — Wiki

**Unraid Drive** puts your Unraid shares into the Files app on iPhone, iPad and Apple Vision Pro, next to iCloud Drive, and adds a small dashboard of your server. It works at home and away (5G, hotel Wi‑Fi) **without a VPN**, thanks to a tiny container that runs on Unraid: [`unraid-gateway`](https://github.com/sidimam/unraid-gateway).

This wiki is a complete, step-by-step guide. Follow the pages in order; every step has the exact clicks and commands. If you only want to see the app, install it and tap **Try the demo**: no server needed.

## Guide

1. [Overview: how it works](Overview)
2. [Step 1 — Install the gateway container on Unraid](Step-1-Install-the-gateway)
3. [Step 2 — Create an Unraid API key](Step-2-Create-an-API-key)
4. [Step 3 — Publish the gateway on the Internet with Cloudflare Tunnel](Step-3-Publish-with-Cloudflare-Tunnel)
5. [Step 4 (optional) — Protect it with Cloudflare Access](Step-4-Protect-with-Cloudflare-Access)
6. [Step 5 — Add the server in the app](Step-5-Add-the-server-in-the-app)
7. [Step 6 — Use your shares in the Files app](Step-6-Using-the-Files-app)
8. [Step 7 — Unraid Drive on the Mac](Step-7-Unraid-Drive-on-the-Mac)
8. [Alternatives to Cloudflare](Alternatives-to-Cloudflare)
9. [Troubleshooting](Troubleshooting)
10. [Security notes](Security)
11. [FAQ](FAQ)

## Highlights

- Files app integration on iPhone, iPad and Apple Vision Pro, working remotely without VPN.
- Authentication with your Unraid API key; optionally your **Unraid user and password**, so each family member sees exactly the shares Unraid grants them.
- Connection modes: Direct, **Cloudflare Access** (service token), Demo (offline sample).
- Read-only dashboard: array, shares, Docker, notifications, CPU/RAM.
- Optional **iCloud sync** of the configuration for painless device restores.
- Built-in **connection test** and server editing.

## What you need

| | |
|---|---|
| Unraid | 7.2 or newer (the built-in Unraid API is required; 7.3 recommended) |
| Community Applications | installed on Unraid (the *Apps* tab) |
| A device | iPhone or iPad with iOS/iPadOS 17 or newer, or Apple Vision Pro |
| For remote access | a free Cloudflare account and a domain managed by Cloudflare (a €5–10/year domain is enough), **or** any reverse proxy with a valid HTTPS certificate |
| Time | about 20 minutes the first time |

## In one picture

```
 iPhone / iPad / Vision Pro                     Internet                         Your home
┌──────────────────────────┐                                              ┌─────────────────────────────┐
│ Files app  ── Unraid Drive│ ── HTTPS ──▶ Cloudflare Tunnel hostname ──▶ │ cloudflared ─▶ unraid-gateway│
│ Unraid Drive app          │              (unraidfile.example.com)       │                :8484         │
└──────────────────────────┘                                              │        │             │       │
                                                                          │   /mnt/user/*   Unraid API   │
                                                                          └─────────────────────────────┘
```

No port is opened on your router. Nothing is stored in any cloud: files travel from your NAS to your device through an encrypted tunnel.
