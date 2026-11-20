# Roadmap

## v0.1: App foundation ✅
- [x] Modern responsive UI for phone, tablet and desktop
- [x] Light/dark themes and accent colours
- [x] Every setting adjustable, searchable, with export/import
- [x] Profiles: Battery Saver, Balanced, High Quality, Gaming, Movies
- [x] Nearby device discovery on the same Wi-Fi
- [x] Automatic builds for all 5 platforms, checksums, attestations

## v0.2: Streaming over Wi-Fi (current)
- [x] Pairing handshake: one-time 6-digit code, HMAC proof, approval prompt
- [x] Screen capture on Android (MediaProjection), Windows, macOS and Linux
- [x] WebRTC video with end-to-end encryption (DTLS-SRTP)
- [x] Quality control from the viewing device: resolution, FPS, bitrate, codec
- [x] Automatic quality adaptation to the network
- [x] Live stats overlay: resolution, FPS, bitrate, codec, ping
- [x] iPhone/iPad can view other screens
- [ ] iPhone/iPad screen sharing (needs a ReplayKit broadcast extension)
- [ ] Choose which monitor or window to share (main screen only for now)
- [ ] System audio streaming

## v0.3: Remote control
- [ ] Mouse, keyboard and touch input to Windows, macOS, Linux and Android
- [ ] Gesture shortcuts and gamepad mode
- [ ] Trusted devices: reconnect without a new code

## v0.4: Connect anywhere
- [ ] USB connection (Android ADB/tethering)
- [ ] Hotspot / Wi-Fi Direct
- [ ] Internet connections via signaling and TURN relay server
- [ ] Stronger pairing (PAKE) for untrusted networks

## v0.5: Extras
- [ ] File transfer and clipboard sync
- [ ] QR code scanning for pairing
- [ ] Screen recording and screenshots
- [ ] Phone as webcam, microphone or second monitor
- [ ] Windows installer, Linux AppImage, Flathub
