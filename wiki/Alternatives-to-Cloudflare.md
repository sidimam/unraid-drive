# Alternatives to Cloudflare

Anything that gives the gateway a **public HTTPS URL with a certificate a stock iPhone trusts** works. iOS File Provider extensions refuse self-signed certificates, so plain `https://<public-ip>:8484` with a home-made certificate does **not** work.

## Reverse proxy on Unraid + port forward

Use **Nginx Proxy Manager** or **SWAG** from Community Applications:

1. Point a DNS name (DuckDNS, your domain, a dynamic-DNS provider) at your public IP. You need a **real public IPv4** (no CGNAT) or working IPv6.
2. Forward TCP **443** on your router to the proxy container.
3. In the proxy create a host `unraidfile.example.com` → `http://192.168.0.100:8484`, request a **Let's Encrypt** certificate, enable *Force SSL* and *HTTP/2*.
4. Keep `TRUST_PROXY=true` on the gateway.

Pros: no third party in the path. Cons: an open port on your router, and it does not work behind CGNAT.

## Tailscale / WireGuard

If you *do* run a VPN on your device, the gateway is just another LAN service: use `http://<tailscale-ip>:8484` or the MagicDNS name. Plain HTTP is accepted by iOS for local/VPN addresses only when the app allows local networking, which Unraid Drive does. Note that only one VPN can be active on iOS at a time.

## Other tunnels

**Pangolin**, **ngrok**, **Tailscale Funnel**, **frp** behind a VPS with Caddy… all fine as long as the result is a public `https://` URL with a valid certificate that forwards to `192.168.0.100:8484`. Set `TRUST_PROXY=true`.

## What does not work

- `http://<public-ip>:8484` with port forwarding: iOS blocks plain HTTP to public addresses in extensions.
- Self-signed or private-CA certificates.
- Exposing the Unraid WebGUI itself: never do that; the gateway is the only thing that should be reachable.
