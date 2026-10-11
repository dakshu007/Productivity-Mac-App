# Signing, notarizing and updating FlowBreak

Builds made without signing credentials are **ad-hoc signed and not notarized**. macOS asks you to approve them on first launch (System Settings › Privacy & Security › Open Anyway). Signing with an Apple Developer ID removes that step. Everything below is optional.

## 1. What you need

- An [Apple Developer Program](https://developer.apple.com/programs/) membership ($99/year).
- A **Developer ID Application** certificate. Create it in Xcode › Settings › Accounts › Manage Certificates, or at developer.apple.com › Certificates.
- An **app-specific password** for notarization, created at [appleid.apple.com](https://appleid.apple.com) › Sign-In and Security › App-Specific Passwords.
- Your **Team ID**, a 10-character code shown at developer.apple.com › Membership.

## 2. Export the certificate

1. Open **Keychain Access** › login › My Certificates.
2. Right-click **Developer ID Application: Your Name (TEAMID)** › Export…, then save as `cert.p12` with a strong password.
3. Base64-encode it:

   ```bash
   base64 -i cert.p12 | pbcopy
   ```

## 3. Add repository secrets

On GitHub, open the repo › Settings › Secrets and variables › Actions › New repository secret.

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERT_P12_BASE64` | the base64 text you copied |
| `DEVELOPER_ID_CERT_PASSWORD` | the `.p12` password |
| `DEVELOPER_ID_APPLICATION` | `Developer ID Application: Your Name (TEAMID)` (exactly as in Keychain) |
| `APPLE_ID` | your Apple ID email |
| `APPLE_TEAM_ID` | your Team ID |
| `APPLE_APP_PASSWORD` | the app-specific password |

The next push then builds `FlowBreak.dmg`, signed with hardened runtime, notarized and stapled. The `-unsigned` suffix disappears, and `latest.json` reports `"notarized": true`.

To sign locally instead:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
xcrun notarytool store-credentials flowbreak --apple-id you@example.com --team-id TEAMID
export NOTARY_PROFILE=flowbreak
Scripts/sign_and_notarize.sh
```

## 4. How updates work today

- CI publishes `latest.json` in the **latest build** release. It lists the version, build number, DMG URL and SHA-256.
- FlowBreak checks it only if you turn on *Check for updates automatically* (once a day) or press **Check Now** in Settings › About.
- **Download & Open** downloads the DMG, verifies the SHA-256 checksum, and marks the file as downloaded so Gatekeeper still checks it. It then opens the DMG for you to drag into Applications.

## 5. Fully automatic installs (later)

Once builds are Developer ID–signed, [Sparkle](https://sparkle-project.org) can replace the app in place. That needs an EdDSA signing key kept as a repo secret and an appcast feed. FlowBreak doesn't do this for unsigned builds, because silently replacing an unverified app would bypass the protection Gatekeeper gives you.
