# Overview: how it works

## The three pieces

1. **Unraid** exposes its management API (GraphQL) on the LAN. The API can tell the app about the array, the shares, Docker containers and notifications, and it validates API keys. It cannot read or write files: that is why piece 2 exists.
2. **unraid-gateway** is a Docker container running on Unraid. It does three jobs:
   - checks the API key you type in the app by asking Unraid *"is this key valid?"*, then hands the app a short-lived session token;
   - serves your shares over HTTPS with a file API built for the Files app (listing, streaming download, resumable upload, move/rename/delete, and a change feed so Files stays in sync);
   - forwards the app's dashboard queries to the Unraid API, so the Unraid web interface itself is never exposed.
3. **Unraid Drive** (this app) contains a *File Provider extension*. That is the same mechanism OneDrive, Google Drive or Dropbox use to appear in the Files app. Anything that can open the Files picker (Mail, Pages, Photos, Safari downloads, third-party apps) can therefore read and write your Unraid shares.

## What gets stored where

| Item | Where | Notes |
|---|---|---|
| Your Unraid API key | The device Keychain, shared only with the extension | Sent only to your own gateway URL, once per session |
| Unraid username and password (optional) | The device Keychain | Sent to your gateway at login; verified by Unraid's Samba |
| iCloud copy (optional, Settings) | iCloud Key-Value Storage (server list) and iCloud Keychain (secrets) | Only when *Sync configuration with iCloud* is on |
| Cloudflare service token (optional) | The device Keychain | Sent as HTTP headers on every request |
| Session token | Memory of the gateway container | Dies when the container restarts; the app logs in again silently |
| File contents | Your NAS | Files opened in the Files app are cached on the device like any cloud provider and can be evicted |
| Nothing | Any third-party cloud | Cloudflare only relays encrypted traffic; it never stores your files |

## Which shares are visible

Only the shares you *mount into the container*. The gateway sees `/data/<name>` for every share you map. A share you do not map does not exist for the app. You can also map a share read-only.

On top of that, when the app logs in with an **Unraid username and password**, the gateway applies that user's SMB share security (Public / Secure / Private with read and write lists) exactly as Unraid does: shares the user may not read disappear, read-only ones stay read-only. Passwords are verified by Unraid's Samba over a real SMB session (with a guest check, since Samba maps unknown users to guest); the gateway stores nothing but the resulting permissions for the session.

## What the app cannot do (by design)

- It cannot delete or rename a share itself (only files and folders inside it).
- It cannot start/stop the array or containers with a `VIEWER` key. If you want the dashboard to *control* things in a future version, you will need an `ADMIN` key; today the app only reads.
- It cannot bypass the mounts: a key with `ADMIN` role does not see more shares than a `VIEWER` key.
