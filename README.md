# BeamX

**Screen sharing and remote control between all your devices:**
Windows, macOS, Linux, Android and iPhone/iPad. Free, open source and
end-to-end encrypted. By **Rajeev Development**.

[![Build](https://github.com/Rajeev0007/BeamX/actions/workflows/build.yml/badge.svg)](https://github.com/Rajeev0007/BeamX/actions/workflows/build.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/Rajeev0007/BeamX/badge)](https://scorecard.dev/viewer/?uri=github.com/Rajeev0007/BeamX)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/Rajeev0007/BeamX)](https://github.com/Rajeev0007/BeamX/releases/latest)

## Download

**[⬇ Latest release](https://github.com/Rajeev0007/BeamX/releases/latest)**.
Step-by-step help for each device: **[install guide](docs/INSTALL.md)**.

| Device | File |
|---|---|
| **Windows** 10/11 | `BeamX-windows-setup.exe` (installer) · `BeamX-windows-x64.zip` (portable) |
| **macOS** | `BeamX-macos.dmg` |
| **Linux** | `BeamX-linux-amd64.deb` (Ubuntu, Debian, Mint) · `BeamX-linux-x64.tar.gz` |
| **Android** | `BeamX-android-arm64.apk` (most phones) · `BeamX-android-armv7.apk` (older phones) · `BeamX-android.apk` (any phone, larger) |
| **Android, to be controlled remotely** | `BeamX-Control-android-arm64.apk` (see [why there are two editions](docs/INSTALL.md#two-android-editions)) |
| **iPhone / iPad** | `BeamX-ios-unsigned.ipa` (install with AltStore or SideStore) |

## What it does

- **Share your screen** to any of your devices, or view theirs, in sharp
  quality: up to 4K, up to 120 FPS, H.264 / H.265 / AV1, adapting to your
  network automatically
- **Remote control:** mouse and keyboard for PCs and Macs, touch for Android,
  with touch gestures, an on-screen keyboard, a **media remote** and a
  **gamepad** when controlling from a phone
- **Sound** from Windows and Linux; **your microphone** to the other device
- **Files** both ways (drag and drop on computers), **shared clipboard**,
  **screenshots** and **recording**
- **Connect from anywhere** with the device's **ID + your password**, like
  AnyDesk, with no setup, or through **your own server** for the best
  reliability ([guide](server/README.md))
- Works over **Wi-Fi, a phone hotspot or a USB cable** too
- Every setting adjustable, saved **profiles**, light/dark themes and layouts
  for phones, tablets and desktops

## Quick start

**Same Wi-Fi, one-time code:**
1. Open BeamX on both devices.
2. On one, tap the other device in the list, choose **View their screen**
   or **Share mine**, and type the code shown on the other device.
3. Tap **Allow** on the other device.

**From anywhere, ID + password:**
1. On the device you want to reach: **Settings → Access from anywhere →**
   turn on **Connect from anywhere** and **Allow connecting with a
   password**, and set a password.
2. On your other device: type its **ID** in **Connect to ID**, then the
   password.

## Is it safe?

- **End-to-end encrypted** video, sound, files and input (WebRTC DTLS-SRTP).
- **You decide who connects:** one-time codes, an Allow prompt, trusted
  devices, or your own password (never stored or sent; locks after 5 wrong
  tries). Hidden devices aren't listed anywhere.
- **Remote control is off** until the owner of the shared device turns it on,
  and a red "Your screen is being shared" banner is always visible.
- **No ads, no tracking, no data collection.**
- **Open source and verifiable:** every release is built by GitHub Actions
  from this code, with SHA-256 checksums and signed build attestations:
  ```
  gh attestation verify BeamX-android-arm64.apk --repo Rajeev0007/BeamX
  ```

Details and how to report a problem: [SECURITY.md](SECURITY.md).

## Known limits

- iPhone/iPad can view and control other devices but can't share its own
  screen yet, and Apple doesn't allow controlling an iPhone remotely.
- Sound sharing works from Windows and Linux; Android and Mac send video only.
- Recording works on Android, iPhone/iPad and Mac.
- Linux screen sharing and remote control need an X11 session.

Planned work: [roadmap](docs/ROADMAP.md).

## For developers

```
app/                Flutter app (one codebase for all 5 platforms)
  lib/services/     Connections, WebRTC sessions, pairing, input, transfers
  lib/screens/      Devices, streaming, transfers, profiles, settings
  native/android/   Accessibility service for remote control (Kotlin)
  tool/             Platform setup, installers, version numbers
server/             Optional internet server (Node.js, no dependencies)
.github/workflows/  Builds, releases, tests, security scorecard
docs/               Install guide, owner setup guide, roadmap
```

Build it yourself with the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable):
```
cd app
python3 tool/prepare_platforms.py
flutter run
```

Repository owner: see the [setup guide](docs/SETUP.md).

## Official builds

Official Android builds are signed by Rajeev Development. The app shows
**✓ Official build** in its footer, or **Unofficial build** for copies signed
by anyone else. On other platforms, check the download against
`SHA256SUMS.txt` or the build attestation (see "Is it safe?" above).

## Licence

Copyright © 2026 **Rajeev Development**. BeamX is free software under the
[GNU GPL v3](LICENSE): you may use, study, share and change it, and shared
changes must stay open source under the same licence. Under the
[additional terms](NOTICE) (GPL-3.0 section 7), every copy must keep the
credit "Originally developed by Rajeev Development", and modified versions
must use a different name.

[Terms of Service](TERMS.md) · [Privacy Policy](PRIVACY.md) · [Notice](NOTICE) · [Security](SECURITY.md)

---
<p align="center">BeamX · © 2026 Rajeev Development · Made in India</p>
