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
- [ ] Custom gesture shortcuts
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

## v0.7: Connect anywhere ✅
- [x] Self-hostable internet server: relay + TURN + automatic HTTPS (server/)
- [x] 9-digit Internet ID, connect from anywhere with ID + pairing code
- [x] One-tap internet connect to trusted devices
- [x] Server tests in CI
- [ ] Stronger pairing (PAKE) against active attackers

## v0.8: ID + password access ✅
- [x] Permanent 9-digit ID on the main screen, with a Connect to ID box
- [x] Owner-set access password (PBKDF2, never stored or sent), lock after 5 wrong tries
- [x] Password connections start without the Allow prompt (optional)
- [x] Hidden devices: not listed anywhere, but reachable by exact ID
- [x] "Connect from anywhere" switch

## v0.9: Zero-setup internet ✅
- [x] "Connect from anywhere" works with no setup, through the free public PeerJS server
- [x] Your own server stays available for reliability and mobile networks (TURN)
- [x] Internet connections check that the answering device really owns the dialed ID

## v0.9.1: Every setting works
- [x] Keep stream window on top (computers)
- [x] Full screen button on the viewer (all platforms)
- [x] Scroll speed applies when controlling
- [x] Removed settings that couldn't work yet: encoder choice (the video
      library picks the hardware encoder), phone screen off while mirroring
      (Android doesn't allow apps to do this), connection type (BeamX always
      picks the best connection automatically)

## v0.10: Feature batch ✅
- [x] Media remote: play/pause, next, previous, volume, slides
      (Windows, Linux, Android; volume and Music/Spotify on Mac)
- [x] Touch gestures when controlling a computer from a phone: tap, hold-drag,
      two-finger scroll, two-finger tap = right-click, three-finger swipes
- [x] On-screen gamepad that presses keys (Arrows or WASD layout)
- [x] Microphone sharing from the viewing device, with mute
- [x] Save your own profiles
- [x] Drag and drop files to send (computers), choose the save folder
- [x] Screen rotation lock (phones)

## v1.0: First stable release (current)
- [x] Sharp quality: fixed phone resolution scaling, higher bitrate limits,
      fast start, smooth-frame-rate mode for 60+ FPS
- [x] Faster response: live touch on Android, separate input channel
- [x] Nearby devices appear reliably on Android (multicast lock)
- [x] Two Android editions: BeamX installs everywhere; BeamX Control can be
      controlled remotely
- [x] © Rajeev Development; About screen, NOTICE, publisher info in installers

## Later
- [ ] Phone notifications, messages and battery on the PC
- [ ] Calls through the PC
- [ ] Phone as second monitor or webcam
- [ ] iPhone screen sharing; Android and Mac system sound
- [ ] Recording on Windows and Linux
- [ ] Whiteboard / drawing on the shared screen
- [ ] More languages
- [ ] Recording on Windows and Linux
- [ ] Phone as webcam, microphone or second monitor
- [ ] Linux AppImage and Flathub
