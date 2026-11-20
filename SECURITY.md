# Security policy

## Reporting a vulnerability

Please report security problems privately through
[GitHub private vulnerability reporting](https://github.com/Rajeev0007/BeamX/security/advisories/new).
Do not open a public issue. You will get a reply within 7 days.

## Supported versions

Only the latest release receives security fixes.

## Security design

- **Pairing:** a device connects only with the 6-digit code shown on the
  other device. Codes come from a cryptographically secure random generator,
  are used once, and are replaced after 5 wrong attempts. The code is never
  sent over the network: the connecting device proves it knows the code with
  HMAC-SHA256 over a random challenge.
- **Access password:** set by the device owner, at least 8 characters.
  The password is never stored or sent. Both devices derive a key with
  PBKDF2-HMAC-SHA256 (150,000 iterations, salted with the device ID), and
  the connecting device proves it has the key with HMAC over a random
  challenge. After 5 wrong passwords in 10 minutes, password access is
  refused for 10 minutes, and each wrong try waits 2 seconds.
- **Hidden devices:** when "Visible nearby" is off, the device is never
  listed. It answers only a request for its exact 9-digit ID.
- **Approval:** by default every connection must be accepted on the other
  device, which shows the requester's name, address and what they want.
- **Encryption:** video is end-to-end encrypted by WebRTC (DTLS-SRTP).
  The offer and answer that set up the encryption are authenticated with the
  pairing code, so another device can't swap them.
- **Consent:** sharing your screen always shows a visible indicator that
  cannot be turned off, and on Android a system notification too.
- **Trusted devices:** when you tick "Trust this device", a new random
  256-bit key is sent over the encrypted WebRTC channel (never over the
  unencrypted signaling connection). Removing a device in Settings revokes
  it immediately. Keys are stored in the app's local settings.
- **Remote control:** off by default. Only the owner of the shared device
  can turn it on (in the Allow prompt, the connect sheet, or the toolbar)
  and off again at any time. Input events are validated (coordinates,
  allowed keys, text length) and ignored while control is off. Held keys
  and buttons are released when control stops. On Android, the
  accessibility service acts only on BeamX session commands and reads no
  screen content. On macOS, BeamX runs outside the App Sandbox because
  sandboxed apps can't control the Mac.
- **Files and clipboard:** sent only over the encrypted WebRTC channel.
  Each incoming file needs your approval. File names are stripped of folders
  and special characters, sizes are checked, and partial files are deleted.
- **Untrusted input:** discovery packets and signaling messages are
  size-limited, strictly validated and sanitised before display.
- **Local first:** without an internet server set, BeamX connects only
  within your local network and contacts no outside servers.
- **Internet mode (optional):** you choose the server (self-hosted, see
  `server/README.md`). It relays setup messages and, when needed, encrypted
  media through TURN. It can't read the stream, and it can't alter the
  setup messages because they're authenticated with the pairing code or
  trust key. Each device claims its ID on the server with a secret key.

### Known limitations (v0.2)

- The local signaling connection (port 47800) is not itself encrypted. Someone
  actively attacking your Wi-Fi network during pairing could capture the
  pairing exchange and try all 1,000,000 codes offline to impersonate a
  device. The approval prompt still has to be accepted. A stronger pairing
  method (PAKE) is planned before internet connections are added.
- Use BeamX on networks you trust, such as your home Wi-Fi.
- **No telemetry:** BeamX does not collect or send usage data.
- **Supply chain:** releases are built only by GitHub Actions, with pinned
  action versions, SHA-256 checksums and signed build provenance.
  Dependabot keeps dependencies updated and OpenSSF Scorecard audits the
  repository weekly.
