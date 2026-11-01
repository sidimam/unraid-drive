# Privacy Policy — Unraid Drive

_Last updated: 11 September 2026_

Unraid Drive is an app for iPhone, iPad, Apple Vision Pro, Mac and Apple TV that connects to **your own** Unraid server through the `unraid-gateway` container you run yourself. It does not use any server operated by the developer.

## Data the app processes

- **Gateway URL, Unraid API key, optional Unraid username and password, optional Cloudflare Access service token.** Entered by you. Stored on your device as part of the server profile, in the app's own container shared only with its extensions. Sent only to the gateway URL you entered, to authenticate. With *Sync configuration with iCloud* on (Settings › iCloud; on by default, you can turn it off), the profiles, credentials included, are stored in your own iCloud account (Key-Value Storage, provided and encrypted by Apple; end-to-end with Advanced Data Protection) so your other devices and a reinstall get them; the readable `servers.json` in iCloud Drive never contains credentials.
- **Your files.** Files you open, save or move are transferred directly between your device and your gateway. Files opened in the Files app are cached on your device like with any cloud provider and can be removed with *Remove Download*.
- **Server information** shown in the dashboard (array, shares, containers, notifications) is read from your Unraid API through your gateway and displayed; it is not stored beyond the app's cache.

## Data the app does not collect

The app contains no analytics, no advertising, no crash-reporting service and no account system. The developer receives no data from the app. Cloudflare, if you choose to use it to publish your gateway, relays encrypted traffic under its own privacy policy and never stores your files.

## Apple TV

Pairing an Apple TV uses a one-time 6-digit code shown on the TV. The server configuration is encrypted with that code and exchanged only through your own iCloud account (Key-Value Storage); the Apple TV then talks directly to your gateway with your Unraid user's permissions.

## Demo server

The demo server is a simulation that lives entirely on your device. Nothing is sent anywhere.

## Your choices

You can delete all data by removing servers in the app (which also deletes their credentials and Files app locations), *Remove the copy from iCloud* in Settings › iCloud and uninstalling the app.

## Contact

Questions: open an issue at https://github.com/sidimam/unraid-drive/issues.
