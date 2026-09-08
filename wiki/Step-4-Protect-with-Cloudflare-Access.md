# Step 4 (optional) — Protect the gateway with Cloudflare Access

After Step 3 anybody on the Internet can reach the gateway's login page. The gateway itself is safe (nothing works without a valid Unraid API key, and brute force is rate-limited), but you can add a second lock **in front** of it so that only requests carrying a secret token ever reach your home. This is the same mechanism Unraid Deck uses.

The app supports it natively: choose **Cloudflare Access** when adding the server and paste the token.

## 4.1 Create a Service Token

1. <https://one.dash.cloudflare.com> → **Access controls → Service credentials** (older UI: *Access → Service Auth → Service Tokens*).
2. **Create Service Token**.
3. **Name**: `Unraid Drive`. **Duration**: *Non-expiring* (or a long duration; you will have to update the app when it expires).
4. Click **Generate token**. Cloudflare shows two values **once**:
   - `CF-Access-Client-Id` — looks like `1234abcd....access`
   - `CF-Access-Client-Secret` — a long hex string
   Copy both into a password manager.

## 4.2 Create an Access application for the hostname

1. **Access controls → Applications** → **Add an application** → **Self-hosted**.
2. **Application name**: `unraid-gateway`.
3. **Session duration**: any.
4. **Public hostname**: subdomain `unraidfile`, domain `example.com` (the hostname from Step 3). Leave *Path* empty.
5. Click **Next** to the policies.

## 4.3 Add a policy that allows the token

1. **Add a policy**. **Policy name**: `Service token`.
2. **Action**: **Service Auth** (not *Allow*: *Service Auth* means "no interactive login, just check the token").
3. Under *Configure rules*: **Selector** = `Service Token`, **Value** = `Unraid Drive` (the token you created).
4. Save the policy, then **Next** and **Add application**.

Optionally add a second policy with action **Allow** and rule *Emails = your e‑mail*, so that *you* can still open the gateway page in a browser through Cloudflare's login screen.

## 4.4 Test

- Opening `https://unraidfile.example.com/healthz` in a browser now shows the Cloudflare Access login page (or a 403): the gateway is no longer reachable without the token. Good.
- From a terminal:
  ```bash
  curl -s https://unraidfile.example.com/healthz \
       -H "CF-Access-Client-Id: <id>" -H "CF-Access-Client-Secret: <secret>"
  ```
  must answer `{"status":"ok",...}`.

## 4.5 In the app

In **Add server** choose **Connection: Cloudflare Access** and paste the two values. The app stores them in the Keychain and adds the two headers to every request, including the ones made by the Files app extension in the background.

→ Next: [Step 5 — Add the server in the app](Step-5-Add-the-server-in-the-app)
