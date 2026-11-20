# Installing BeamX

Download files from the [Releases page](https://github.com/Rajeev0007/BeamX/releases).
Preview releases are marked **Pre-release**.

BeamX is free and not sold through app stores, so some systems ask you to
confirm the install once. This is normal for apps downloaded from the web.
You can confirm the file is genuine with [the steps at the end](#verify-your-download).

## Android

1. Download `BeamX-android.apk` on your phone
   (in preview releases it's named `BeamX-android-preview.apk`).
2. Open it. If asked, tap **Settings** and turn on **Allow from this source**
   for your browser or file manager.
3. Tap **Install**. If Play Protect shows a warning about an unknown app,
   tap **More details → Install anyway**.

When you first share your screen, Android asks:
- **Allow notifications**: tap **Allow**. The notification shows while sharing.
- **Start recording or casting with BeamX?**: choose **Entire screen** and tap **Start**.
- **Run in background** (battery optimisation): tap **Allow**, so sharing
  doesn't stop when you switch apps.

If your installed BeamX is named `BeamX-android-preview.apk` (v0.1.0-preview),
uninstall it before installing a newer version. It used a temporary signing key.

## Windows

1. Download `BeamX-windows-x64.zip` and extract it.
2. Open `beamx.exe`.
3. If you see **"Windows protected your PC"**, click **More info → Run anyway**.
   This message appears until BeamX's free code-signing certificate is approved.
4. When **Windows Defender Firewall** asks, tick **Private networks** and
   click **Allow access**. Without this, other devices can't connect to this PC.

## macOS

1. Download `BeamX-macos.dmg`, open it and drag **BeamX** into **Applications**.
2. The first time, **right-click BeamX → Open → Open**.
   If macOS still blocks it, go to **System Settings → Privacy & Security**
   and click **Open Anyway**.
3. The first time you share, allow **Screen Recording** for BeamX in
   **System Settings → Privacy & Security → Screen & System Audio Recording**,
   then reopen BeamX.
4. If macOS asks whether BeamX may find devices on your local network,
   click **Allow**.

## Linux

```
mkdir -p ~/BeamX && tar -xzf BeamX-linux-x64.tar.gz -C ~/BeamX
~/BeamX/beamx
```

Screen sharing from Linux works best in an **X11** session. On Wayland,
sharing may not work yet; viewing other screens works on both.

## iOS (iPhone / iPad)

Apple only allows apps from outside the App Store through sideloading tools.

1. Install [AltStore](https://altstore.io) or [SideStore](https://sidestore.io)
   by following their guide.
2. Download `BeamX-ios-unsigned.ipa` and open it with AltStore or SideStore.
3. Sign in with your own free Apple ID when asked.

With a free Apple ID, sideloaded apps must be refreshed every 7 days.
AltStore and SideStore can do this automatically.

When BeamX asks to find devices on your local network, tap **Allow**.

**iOS limitations:**
- An iPhone or iPad can **view** other screens. Sharing the iPhone's own
  screen isn't available yet.
- Apple does not let any app control an iPhone remotely.
- iPhones can't discover devices automatically. On the other device, tap
  **Pair** and connect by address, or connect from the iPhone by typing the
  other device's IP address.

## Verify your download

Every release file was built by GitHub Actions from this repository's code.

- **Checksum:** compare your file's SHA-256 with `SHA256SUMS.txt` in the release.
  - Windows: `certutil -hashfile BeamX-windows-x64.zip SHA256`
  - macOS / Linux: `shasum -a 256 BeamX-macos.dmg`
- **Build attestation** (needs the [GitHub CLI](https://cli.github.com)):
  ```
  gh attestation verify BeamX-android.apk --repo Rajeev0007/BeamX
  ```
