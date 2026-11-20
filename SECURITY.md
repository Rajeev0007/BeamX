# Security policy

## Reporting a vulnerability

Please report security problems privately through
[GitHub private vulnerability reporting](https://github.com/Rajeev0007/BeamX/security/advisories/new).
Do not open a public issue. You will get a reply within 7 days.

## Supported versions

Only the latest release receives security fixes.

## Security design

- **Pairing:** devices connect only after the user enters a one-time 6-digit
  code or scans a QR code. Codes come from a cryptographically secure random
  generator.
- **Encryption:** all streams, input and file transfers will use end-to-end
  encryption (DTLS-SRTP via WebRTC, TLS for control channels). Unencrypted
  connections are not offered.
- **Consent:** sharing your screen always shows a visible indicator that
  cannot be turned off.
- **Untrusted input:** network discovery packets are size-limited, strictly
  validated and sanitised before display.
- **No telemetry:** BeamX does not collect or send usage data.
- **Supply chain:** releases are built only by GitHub Actions, with pinned
  action versions, SHA-256 checksums and signed build provenance.
  Dependabot keeps dependencies updated and OpenSSF Scorecard audits the
  repository weekly.
