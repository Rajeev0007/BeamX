# BeamX owner setup guide

Everything you (the repository owner) need to set up, in order. Every step
works in a phone browser unless it says **PC**.

Tip: in the GitHub mobile site, tap the **⋯** menu or switch to **Desktop
site** in your browser menu if you can't find **Settings**.

---

## Already done for you

- [x] Code, licence (GPL-3.0), README, install guide, security policy
- [x] Automatic builds for Android, Windows, macOS, Linux and iOS
- [x] Release pipeline with checksums and signed build attestations
- [x] Dependabot version updates and weekly OpenSSF security scorecard
- [x] Public releases up to **v1.0.0**
- [x] Two Android editions, so the main one isn't blocked by Play Protect

## Checklist

| # | Task | Time | Needed for |
|---|---|---|---|
| 1 | [Repository settings](#1-repository-settings) | 5 min | Security and discoverability |
| 2 | [Android signing key](#2-android-signing-key) | 20 min | **Stable releases** (v0.2.0 and later) |
| 3 | [Publish a release](#3-publish-a-release) | 2 min | Each new version |
| 4 | [Free Windows signing](#4-free-windows-signing-signpath) | 15 min + waiting | Removing the SmartScreen warning |
| 5 | [Android developer verification](#5-android-developer-verification) | 15 min | Installs in 2027 and later |
| 6 | [Internet server](../server/README.md) (optional) | 30 min | Most reliable "connect from anywhere" |
| 7 | [Play Protect review](#7-play-protect-review) (optional) | 20 min | Fewer warnings for BeamX Control |

---

## 1. Repository settings

### 1a. About section
1. Open <https://github.com/Rajeev0007/BeamX>.
2. Next to **About**, tap the **gear icon**.
3. Description: `Fast, secure screen sharing and remote control between Windows, macOS, Linux, Android and iOS. Free and open source.`
4. Topics: `screen-sharing`, `remote-desktop`, `screen-mirroring`, `flutter`,
   `android`, `ios`, `windows`, `macos`, `linux`, `open-source`
5. Tick **Releases**. Tap **Save changes**.

### 1b. Security features
Go to **Settings → Advanced Security** (on some accounts it's named
**Code security**) and turn on:

- **Private vulnerability reporting** (lets people report security bugs privately)
- **Dependabot alerts**
- **Dependabot security updates**

### 1c. Actions permissions
Go to **Settings → Actions → General**:

- **Actions permissions:** *Allow all actions and reusable workflows*
- **Workflow permissions:** keep *Read repository contents and packages
  permissions*. The release job asks for write access on its own.

---

## 2. Android signing key

This key proves that every BeamX update really comes from you. Android only
installs an update if it's signed with the same key as the installed app.

> ⚠️ **Never share the key file or its passwords with anyone, including AI
> assistants. Never commit it to GitHub.** If you lose it, every user has to
> uninstall BeamX before they can install the next version. Keep two backups.

### 2a. Create the key

Choose **one** option.

**Option A: on Android (no PC), using Termux**

1. Install **Termux** from [F-Droid](https://f-droid.org/packages/com.termux/)
   (the Play Store version is outdated).
2. Open Termux and run these lines one at a time:
   ```
   pkg update -y && pkg install -y openjdk-17
   termux-setup-storage
   cd ~/storage/downloads
   keytool -genkeypair -v -keystore beamx-release.jks -alias beamx -keyalg RSA -keysize 4096 -validity 10000
   ```
   Tap **Allow** when Termux asks for storage access.
3. `keytool` asks for a password. Use **at least 16 characters** and write it
   down. Answer the name questions (anything is fine; press Enter to skip).
   When asked for a separate key password, press **Enter** to reuse the same one.
4. Make the text version that GitHub needs:
   ```
   base64 -w0 beamx-release.jks > beamx-release-base64.txt
   ```
   Both files are now in your phone's **Downloads** folder.

**Option B: on a PC (Windows, macOS or Linux)**

1. Install Java 17 or newer from <https://adoptium.net>.
2. Open a terminal (Windows: **PowerShell**) in a folder you choose and run:
   ```
   keytool -genkeypair -v -keystore beamx-release.jks -alias beamx -keyalg RSA -keysize 4096 -validity 10000
   ```
3. Make the text version:
   - Windows PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("beamx-release.jks")) > beamx-release-base64.txt`
   - macOS: `base64 -i beamx-release.jks -o beamx-release-base64.txt`
   - Linux: `base64 -w0 beamx-release.jks > beamx-release-base64.txt`

### 2b. Back it up
Save `beamx-release.jks` **and** the password in two separate places, for
example a password manager plus a USB drive or a private Google Drive folder.

### 2c. Add the key to GitHub
1. Go to **Settings → Secrets and variables → Actions**.
2. Tap **New repository secret** and add these four, one at a time:

| Name | Secret value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | The entire contents of `beamx-release-base64.txt` (open it in a text editor, select all, copy) |
| `ANDROID_KEYSTORE_PASSWORD` | Your keystore password |
| `ANDROID_KEY_ALIAS` | `beamx` |
| `ANDROID_KEY_PASSWORD` | Your key password (the same one, if you pressed Enter) |

3. Delete `beamx-release-base64.txt` from Downloads. You only keep the `.jks`
   backups.

To check it works: go to **Actions → Build → Run workflow**. In the
**android** job, the "Sign with release key" step should print your
certificate instead of a warning.

---

## 3. Publish a release

1. Go to **Releases → Draft a new release**
   (<https://github.com/Rajeev0007/BeamX/releases/new>).
2. Tap **Choose a tag**, type the new version, and tap **Create new tag on publish**:
   - `v0.2.0` = **stable** release (needs the Android key from step 2)
   - `v0.2.0-preview` = **preview** release (allowed without the key; marked as pre-release)
3. Title: `BeamX v0.2.0`. Leave the description empty; it's filled in automatically.
4. Tap **Publish release**.
5. Open the **Actions** tab. In about 10 minutes the build finishes and
   attaches all files, checksums and attestations to the release.

Version numbers must always go up: `0.1.0` → `0.2.0` → `0.2.1` → `1.0.0`.

---

## 4. Free Windows signing (SignPath)

Removes the "Windows protected your PC" warning. SignPath Foundation signs
open-source projects for free. Apply once BeamX has a stable release and some
activity, because they review each project.

1. Read the conditions at <https://signpath.org/terms.html>. Key points:
   OSI licence (BeamX: GPL-3.0 ✓), builds only in CI (✓), no malware (✓),
   and SignPath Foundation is shown as the certificate publisher.
2. Apply through <https://signpath.org>.
3. When approved, they give you an organisation ID and project details.
   Tell your developer (or Kiro) and the signing step gets added to the
   `windows` job in `.github/workflows/build.yml`.

---

## 5. Android developer verification

From 2027, Android phones worldwide (including India) will only install apps
from verified developers without extra steps. Enforcement already started on
30 September 2026 in Brazil, Indonesia, Singapore and Thailand.

Before 2027:
1. Create an Android Developer Console account by following Google's guide:
   <https://developer.android.com/developer-verification/guides/android-developer-console>
   (for apps distributed only outside Google Play, like BeamX).
2. Verify your identity.
3. Register the app with package name **`io.github.rajeev0007.beamx`** and
   your signing key from step 2. The console explains how to prove you own the key.

---

## 7. Play Protect review

Play Protect can block or warn about apps installed from outside the Play
Store, especially **BeamX Control**, which has an accessibility service.
The main **BeamX** edition leaves that service out so it installs normally.

To reduce warnings over time:
1. Complete [Android developer verification](#5-android-developer-verification)
   and register `io.github.rajeev0007.beamx` with your signing key. Apps from
   verified developers are treated as lower risk.
2. If Play Protect flags BeamX, Google lets developers appeal a Play Protect
   classification they believe is wrong. Google's
   [developer guidance for Play Protect warnings](https://developers.google.com/android/play-protect/warning-dev-guidance)
   explains the process. Include a link to this repository and explain that
   the accessibility service is only used for remote control the phone's
   owner turns on.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| A build shows a red ✗ | Open **Actions**, tap the failed run, then the red job, to see the error. Re-run with **Re-run failed jobs** if it looks like a temporary GitHub problem. |
| `hdiutil: create failed - Resource busy` | Temporary macOS runner problem. The workflow retries 5 times; if it still fails, re-run the job. |
| "Stable releases need the ANDROID_KEYSTORE_* secrets" | Finish step 2, delete the failed release and its tag, and publish again. Or use a `-preview` tag. |
| Play Protect says "Unsafe app blocked" | Install the main **BeamX** edition, which has no accessibility service. See [INSTALL.md](INSTALL.md#two-android-editions). |
| Android says "App not installed" when updating | The new APK has a different key than the installed one. Uninstall BeamX, then install the new APK. This happens once, when moving from preview builds to the permanent key. |
| Dependabot PR fails its checks | Comment `@dependabot rebase` on the PR. If it still fails, ask your developer to look. |
