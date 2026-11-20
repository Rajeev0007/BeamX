# Installing BeamX

Download files from the [latest release](https://github.com/Rajeev0007/BeamX/releases/latest).

BeamX is free and not sold through app stores, so some systems ask you to
confirm the install once. This is normal for apps downloaded from the web.
You can confirm the file is genuine with [the steps at the end](#verify-your-download).

## Android

1. Download `BeamX-android.apk` on your phone.
2. Open it. If asked, tap **Settings** and turn on **Allow from this source**
   for your browser or file manager.
3. Tap **Install**.

## Windows

1. Download `BeamX-windows-x64.zip` and extract it.
2. Open `beamx.exe`.
3. If you see **"Windows protected your PC"**, click **More info → Run anyway**.
   This message appears until BeamX's free code-signing certificate is approved.

## macOS

1. Download `BeamX-macos.dmg`, open it and drag **BeamX** into **Applications**.
2. The first time, **right-click BeamX → Open → Open**.
   If macOS still blocks it, go to **System Settings → Privacy & Security**
   and click **Open Anyway**.
3. Allow **Screen Recording** and **Accessibility** when BeamX asks. These
   are needed to share your screen and to be controlled remotely.

## Linux

```
mkdir -p ~/BeamX && tar -xzf BeamX-linux-x64.tar.gz -C ~/BeamX
~/BeamX/beamx
```

## iOS (iPhone / iPad)

Apple only allows apps from outside the App Store through sideloading tools.

1. Install [AltStore](https://altstore.io) or [SideStore](https://sidestore.io)
   by following their guide.
2. Download `BeamX-ios-unsigned.ipa` and open it with AltStore or SideStore.
3. Sign in with your own free Apple ID when asked.

With a free Apple ID, sideloaded apps must be refreshed every 7 days.
AltStore and SideStore can do this automatically.

**iOS limitation:** Apple does not let any app control an iPhone remotely.
An iPhone can share its screen and control other devices, but it cannot
be controlled.

## Verify your download

Every release file was built by GitHub Actions from this repository's code.

- **Checksum:** compare your file's SHA-256 with `SHA256SUMS.txt` in the release.
  - Windows: `certutil -hashfile BeamX-windows-x64.zip SHA256`
  - macOS / Linux: `shasum -a 256 BeamX-macos.dmg`
- **Build attestation** (needs the [GitHub CLI](https://cli.github.com)):
  ```
  gh attestation verify BeamX-android.apk --repo Rajeev0007/BeamX
  ```
