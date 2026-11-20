# BeamX

Fast, secure screen sharing and remote control between all your devices:
**Windows, macOS, Linux, Android and iOS**. Free and open source.

[![Build](https://github.com/Rajeev0007/BeamX/actions/workflows/build.yml/badge.svg)](https://github.com/Rajeev0007/BeamX/actions/workflows/build.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/Rajeev0007/BeamX/badge)](https://scorecard.dev/viewer/?uri=github.com/Rajeev0007/BeamX)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

> **Status: v0.10 (preview).** Live screen sharing and remote control over
> the same Wi-Fi work between Windows, macOS, Linux and Android, and
> iPhones can view and control. Sound is shared from Windows and Linux.
> File transfer, clipboard, trusted devices, QR pairing, screenshots,
> recording, USB/hotspot and internet connections (with your own free
> server, see [server/README.md](server/README.md)) work too. See the
> [roadmap](docs/ROADMAP.md).

## Download

Get the latest version from [Releases](https://github.com/Rajeev0007/BeamX/releases).
Step-by-step instructions for each platform are in the [install guide](docs/INSTALL.md).

| Platform | File |
|---|---|
| Windows 10/11 (64-bit) | `BeamX-windows-setup.exe` (installer) or `BeamX-windows-x64.zip` (portable) |
| macOS | `BeamX-macos.dmg` |
| Linux (x64) | `BeamX-linux-amd64.deb` (Ubuntu/Debian) or `BeamX-linux-x64.tar.gz` |
| Android | `BeamX-android-arm64.apk` (most phones), `BeamX-android-armv7.apk` (older phones) or `BeamX-android.apk` (works on all, larger) |
| iPhone / iPad | `BeamX-ios-unsigned.ipa` (install with AltStore or SideStore) |

**Repository owner?** See the [setup guide](docs/SETUP.md).

## Is it safe?

- **Open source.** Every line of code is public in this repository.
- **Built by GitHub, not on a personal PC.** Every release file is built by
  [GitHub Actions](.github/workflows/build.yml) from the public code.
- **Verifiable.** Each release includes `SHA256SUMS.txt` and a signed build
  attestation. Check any file with:
  ```
  gh attestation verify BeamX-android.apk --repo Rajeev0007/BeamX
  ```
- **No ads, no tracking, no data collection.**
- **You stay in control.** Nothing connects without a pairing code, and a
  red "Your screen is being shared" banner is always visible while sharing.

See [SECURITY.md](SECURITY.md) for how to report a problem.

## How to use

**With ID and password (like AnyDesk):**
1. On the device you want to reach, open **Settings → Access from anywhere**,
   turn on **Allow connecting with a password** and set a password.
   To reach it from other networks, also turn on **Connect from anywhere**
   (no setup needed). Hide it from nearby lists with the switch on the main
   screen.
2. Note its **Your ID** from the main screen.
3. On the other device, type that ID in **Connect to ID**, choose
   **View their screen**, enter the password and tap **Connect**.

**With a one-time code (nobody needs a password):**
1. Open BeamX on both devices, connected to the **same Wi-Fi**.
2. On the first device, tap the other device in the list (or tap **Pair →
   Connect by address** and type its IP).
3. Choose **View their screen** or **Share mine**.
4. Type the **pairing code** shown on the other device's Devices screen,
   or scan its QR code (Devices → Pair) with the scan button.
5. Tap **Allow** on the other device. The stream starts.

Tap the screen to show the toolbar: disconnect, send files, live stats and
quality. Tick **Trust this device** when allowing a connection, and next
time it connects without a code.

## Features

- Live screen sharing in both directions over Wi-Fi, end-to-end encrypted
- Choose resolution (up to 4K), frame rate (up to 120 FPS), bitrate and
  codec (H.264, H.265, AV1); quality also adapts to the network
- Sound from shared Windows and Linux screens, with a mute button
- Screenshots and recording of the stream
- Works over Wi-Fi, a phone hotspot, a USB cable (Android tethering) or the
  internet: no setup with the free public server, or through your own server
  for the best reliability ([guide](server/README.md))
- Live stats: resolution, FPS, bitrate, codec and ping
- Nearby devices appear automatically on the same Wi-Fi
- Pair with a one-time 6-digit code, QR code or IP address, and approve
  every connection; trusted devices reconnect without a code
- Remote control: mouse and keyboard for PCs and Macs, touch for Android,
  only when the owner of the shared device allows it
- Media remote, touch gestures and an on-screen gamepad when controlling
- Microphone sharing from the viewing device
- Send files both ways (up to 4 GB each), including drag and drop, with accept/decline on the other side
- Shared clipboard: copy text on one device, paste on the other
- Pick which monitor to share on multi-screen PCs
- Profiles: Battery Saver, Balanced, High Quality, Gaming, Movies
- Every setting is adjustable: resolution up to 4K, 30–120 FPS, bitrate,
  codec (H.264, H.265, AV1), audio, connection type, controls, theme and colours
- Searchable settings, plus export and import
- Light and dark themes, six accent colours, and layouts for phones,
  tablets and desktops

## Project layout

```
app/                Flutter app (one codebase for all 5 platforms)
server/             Internet relay server (Node.js, no dependencies) + Docker setup
  lib/models/       Settings, profiles, devices
  lib/services/     Settings, discovery, pairing, signaling, WebRTC sessions
  lib/screens/      Devices, pairing, streaming, transfers, profiles, settings
  tool/             Generates and configures native platform folders
.github/workflows/  Builds, releases, security scorecard
docs/               Install guide, owner setup guide, roadmap
```

## Build it yourself

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel).

```
cd app
python3 tool/prepare_platforms.py   # creates android/, ios/, windows/ ...
flutter run
```

## License

[GPL-3.0](LICENSE). You may use, study, change and share BeamX. Shared
changes must stay open source under the same licence.
