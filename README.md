# BeamX

Fast, secure screen sharing and remote control between all your devices:
**Windows, macOS, Linux, Android and iOS**. Free and open source.

[![Build](https://github.com/Rajeev0007/BeamX/actions/workflows/build.yml/badge.svg)](https://github.com/Rajeev0007/BeamX/actions/workflows/build.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/Rajeev0007/BeamX/badge)](https://scorecard.dev/viewer/?uri=github.com/Rajeev0007/BeamX)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

> **Status: v0.1 (early preview).** The app, its settings, profiles and
> nearby-device discovery work. Live screen streaming, remote control and
> file transfer are being built next; see the [roadmap](docs/ROADMAP.md).

## Download

Get the latest version from [Releases](https://github.com/Rajeev0007/BeamX/releases).
Step-by-step instructions for each platform are in the [install guide](docs/INSTALL.md).

| Platform | File |
|---|---|
| Windows 10/11 (64-bit) | `BeamX-windows-x64.zip` |
| macOS | `BeamX-macos.dmg` |
| Linux (x64) | `BeamX-linux-x64.tar.gz` |
| Android | `BeamX-android.apk` (preview releases: `BeamX-android-preview.apk`) |
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

## Features

- Share your screen and view other screens, in both directions
- Nearby devices appear automatically on the same Wi-Fi
- Pair with a QR code, 6-digit code or IP address
- Profiles: Battery Saver, Balanced, High Quality, Gaming, Movies
- Every setting is adjustable: resolution up to 4K, 30–120 FPS, bitrate,
  codec (H.264, H.265, AV1), audio, connection type, controls, theme and colours
- Searchable settings, plus export and import
- Light and dark themes, six accent colours, and layouts for phones,
  tablets and desktops

## Project layout

```
app/                Flutter app (one codebase for all 5 platforms)
  lib/models/       Settings, profiles, devices
  lib/services/     Settings storage, local network discovery
  lib/screens/      Devices, pairing, streaming, transfers, profiles, settings
  tool/             Generates and configures native platform folders
.github/workflows/  Builds, releases, security scorecard
docs/               Install guide, signing, roadmap
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
