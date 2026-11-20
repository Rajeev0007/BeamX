# Code signing (maintainer notes)

BeamX uses only free signing options.

| Platform | Method | Status |
|---|---|---|
| Android | Own release key, applied in CI | Needs the secrets below |
| Windows | [SignPath Foundation](https://signpath.org) free OSS certificate | Apply after the first public release |
| macOS | Ad-hoc signature (runs, but Gatekeeper asks once) | Done in CI |
| iOS | Unsigned IPA, users sign with AltStore/SideStore | Done in CI |
| Linux | No signing needed | — |

## Android release key (one time)

Create the key on your own computer (needs Java). **Back it up safely.** If
you lose it, users must uninstall BeamX before they can install updates.

```
keytool -genkeypair -v -keystore beamx-release.jks -alias beamx \
  -keyalg RSA -keysize 4096 -validity 10000
```

Then add four repository secrets under **Settings → Secrets and variables →
Actions**:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Output of `base64 -w0 beamx-release.jks` (macOS: `base64 -i beamx-release.jks`) |
| `ANDROID_KEYSTORE_PASSWORD` | The keystore password |
| `ANDROID_KEY_ALIAS` | `beamx` |
| `ANDROID_KEY_PASSWORD` | The key password |

Never commit the `.jks` file. `.gitignore` blocks it.

## Windows: SignPath Foundation

SignPath signs open-source releases for free. Their requirements include an
OSI-approved licence (BeamX uses GPL-3.0), builds done entirely in CI, and
no malware or unwanted behaviour. Apply through <https://signpath.org>
once a first release exists. After approval, add their signing step to
`.github/workflows/build.yml` in the `windows` job.

## Android developer verification

Google requires apps on certified Android devices to come from verified
developers. Enforcement started on 30 September 2026 in Brazil, Indonesia,
Singapore and Thailand and expands worldwide in 2027. Register BeamX's
package name `io.github.rajeev0007.beamx` and signing key in the
Android Developer Console before enforcement reaches India.
