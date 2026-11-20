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
- **Approval:** by default every connection must be accepted on the other
  device, which shows the requester's name, address and what they want.
- **Encryption:** video is end-to-end encrypted by WebRTC (DTLS-SRTP).
  The offer and answer that set up the encryption are authenticated with the
  pairing code, so another device can't swap them.
- **Consent:** sharing your screen always shows a visible indicator that
  cannot be turned off, and on Android a system notification too.
- **Untrusted input:** discovery packets and signaling messages are
  size-limited, strictly validated and sanitised before display.
- **Local only:** v0.2 connects only within your local network and contacts
  no outside servers.

### Known limitations (v0.2)

- The signaling connection (port 47800) is not itself encrypted. Someone
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
