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

## v0.3: Transfers and trust ✅
- [x] File transfer in both directions, with accept/decline, over the encrypted channel
- [x] Shared clipboard (text), with direction control in Settings
- [x] Trusted devices: reconnect without a code, remove any time in Settings
- [x] QR code pairing (scan on Android, iPhone/iPad and Mac)

## v0.4: Remote control ✅
- [x] Mouse and keyboard control of Windows, macOS and Linux (X11)
- [x] Touch control of Android: tap, long press, swipe, typing, Back/Home/Recents
- [x] Control from a phone or tablet: touch as mouse, on-screen keyboard
- [x] Consent: off by default, switchable any time on the shared device
- [x] Smaller Android APKs per phone type
- [ ] Gamepad mode and custom gesture shortcuts
- [ ] Control of a second monitor (main screen only for now)

## v0.5: Sound ✅
- [x] Stream the system sound of Windows (WASAPI loopback) and Linux (PulseAudio / PipeWire)
- [x] Mute button on the viewing device
- [x] Turn sound off in Settings → Audio
- [ ] System sound from Android and macOS (needs native audio capture)
- [ ] Microphone sharing

## v0.6: Extras ✅
- [x] Screenshots of the stream on every platform
- [x] Recording the stream to MP4 on Android, iPhone/iPad and Mac
- [x] Windows installer with Start menu entry and firewall rule
- [x] Linux .deb package
- [x] Phone hotspot and USB tethering connections, with discovery on every network

## v0.7: Connect anywhere (current)
- [x] Self-hostable internet server: relay + TURN + automatic HTTPS (server/)
- [x] 9-digit Internet ID, connect from anywhere with ID + pairing code
- [x] One-tap internet connect to trusted devices
- [x] Server tests in CI
- [ ] Stronger pairing (PAKE) against active attackers

## Later
- [ ] Recording on Windows and Linux
- [ ] Phone as webcam, microphone or second monitor
- [ ] Linux AppImage and Flathub
