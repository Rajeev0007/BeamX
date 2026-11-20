# Roadmap

## v0.1: App foundation ✅
- [x] Modern responsive UI for phone, tablet and desktop
- [x] Light/dark themes and accent colours
- [x] Every setting adjustable, searchable, with export/import
- [x] Profiles: Battery Saver, Balanced, High Quality, Gaming, Movies
- [x] Nearby device discovery on the same Wi-Fi
- [x] Automatic builds for all 5 platforms, checksums, attestations

## v0.2: Streaming over Wi-Fi ✅
- [x] Pairing handshake: one-time 6-digit code, HMAC proof, approval prompt
- [x] Screen capture on Android (MediaProjection), Windows, macOS and Linux
- [x] WebRTC video with end-to-end encryption (DTLS-SRTP)
- [x] Quality control from the viewing device: resolution, FPS, bitrate, codec
- [x] Automatic quality adaptation to the network
- [x] Live stats overlay: resolution, FPS, bitrate, codec, ping
- [x] iPhone/iPad can view other screens
- [ ] iPhone/iPad screen sharing (needs a ReplayKit broadcast extension)
- [x] Choose which monitor to share (asks when there are several)
- [ ] System audio streaming

## v0.3: Transfers and trust ✅
- [x] File transfer in both directions, with accept/decline, over the encrypted channel
- [x] Shared clipboard (text), with direction control in Settings
- [x] Trusted devices: reconnect without a code, remove any time in Settings
- [x] QR code pairing (scan on Android, iPhone/iPad and Mac)

## v0.4: Remote control (current)
- [x] Mouse and keyboard control of Windows, macOS and Linux (X11)
- [x] Touch control of Android: tap, long press, swipe, typing, Back/Home/Recents
- [x] Control from a phone or tablet: touch as mouse, on-screen keyboard
- [x] Consent: off by default, switchable any time on the shared device
- [x] Smaller Android APKs per phone type
- [ ] Gamepad mode and custom gesture shortcuts
- [ ] Control of a second monitor (main screen only for now)

## v0.5: Connect anywhere
- [ ] USB connection (Android ADB/tethering)
- [ ] Hotspot / Wi-Fi Direct
- [ ] Internet connections via signaling and TURN relay server
- [ ] Stronger pairing (PAKE) for untrusted networks

## v0.6: Extras
- [ ] Screen recording and screenshots
- [ ] Phone as webcam, microphone or second monitor
- [ ] Windows installer, Linux AppImage, Flathub
