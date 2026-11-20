# Installing BeamX

Download files from the [Releases page](https://github.com/Rajeev0007/BeamX/releases).
Use the newest release that isn't marked **Pre-release**.

BeamX is free and not sold through app stores, so some systems ask you to
confirm the install once. This is normal for apps downloaded from the web.
You can confirm the file is genuine with [the steps at the end](#verify-your-download).

## Android

### Two Android editions

| Edition | Files | Installs everywhere? | Can this phone be remote-controlled? |
|---|---|---|---|
| **BeamX** (recommended) | `BeamX-android-arm64.apk`, `-armv7.apk`, `BeamX-android.apk` | ✅ Yes | ❌ No. It can still share its screen, view and control other devices, and send files. |
| **BeamX Control** | `BeamX-Control-android-arm64.apk`, `BeamX-Control-android.apk` | ⚠️ May be blocked by Play Protect in India and some other countries | ✅ Yes |

**Why two?** Being controlled remotely needs an Android *accessibility
service*. Google Play Protect's "enhanced fraud protection" (India, Brazil,
Singapore, Thailand and more) automatically blocks installing downloaded
apps that contain one, because scammers misuse them. The main edition leaves
it out so it installs normally. Both editions are signed with the same key,
so you can switch by installing the other one over it.

### Install
1. Download the APK on your phone:
   - `BeamX-android-arm64.apk`: most phones from 2017 onwards (smallest)
   - `BeamX-android-armv7.apk`: older phones
   - `BeamX-android.apk`: any phone, larger download
2. Open it. If asked, tap **Settings** and turn on **Allow from this source**
   for your browser or file manager.
3. Tap **Install**. If Play Protect shows **"Unsafe app blocked"** or an
   unknown-developer warning, tap **More details → Install anyway**.

Stay with the same file type for updates. Moving from an arm64/armv7 file
to `BeamX-android.apk` needs an uninstall first.

### First time you share your screen
- **Allow notifications:** tap **Allow** (the notification shows while sharing).
- **Start recording or casting with BeamX?** Choose **Entire screen**, tap **Start**.
- **Run in background:** tap **Allow**, so sharing continues when you switch apps.

### Letting a computer control this phone (BeamX Control only)
1. Install **BeamX Control**. If Play Protect blocks it, see below.
2. Open **Settings → Accessibility → Installed apps** (or **Downloaded apps**)
   and turn on **BeamX remote control**.
3. If Android says **Restricted setting**, open **Settings → Apps → BeamX**,
   tap **⋮ → Allow restricted settings**, then repeat step 2.

The service only acts while you allow remote control in a session, and
reads no screen content.

**If Play Protect blocks BeamX Control:** there is no setting in BeamX that
can override Play Protect. Your options are:
- Use the main **BeamX** edition (everything except being controlled), or
- Temporarily turn off **Play Store → profile icon → Play Protect → ⚙ →
  Scan apps with Play Protect**, install, then turn it back on. Only do this
  for files from the official Releases page, after checking the checksum.

## Windows

**Installer (recommended):**
1. Download `BeamX-windows-setup.exe` and open it.
2. If you see **"Windows protected your PC"**, click **More info → Run anyway**.
   This message appears until BeamX's free code-signing certificate is approved.
3. Click **Yes** when Windows asks for permission, then follow the steps.
   The installer adds BeamX to the Start menu and allows it through Windows
   Defender Firewall, so there's no firewall popup. (Windows 11 often marks
   home Wi-Fi as "Public"; the rule covers both.)

**Portable zip (no install):**
1. Download `BeamX-windows-x64.zip`, extract it and open `beamx.exe`.
2. When **Windows Defender Firewall** asks, tick **both Private and Public
   networks** and click **Allow access**. Without this, other devices can't
   connect to this PC. Windows 11 often marks home Wi-Fi as Public.

Remote control can't reach apps running **as administrator** unless BeamX
is also run as administrator. This is a Windows security rule.

## macOS

1. Download `BeamX-macos.dmg`, open it and drag **BeamX** into **Applications**.
2. The first time, **right-click BeamX → Open → Open**.
   If macOS still blocks it, go to **System Settings → Privacy & Security**
   and click **Open Anyway**.
3. The first time you share, allow **Screen Recording** for BeamX in
   **System Settings → Privacy & Security → Screen & System Audio Recording**,
   then reopen BeamX.
4. If macOS asks whether BeamX may find devices on your local network,
   click **Allow**.
5. To let another device **control this Mac**, allow BeamX in
   **System Settings → Privacy & Security → Accessibility**.

## Linux

**Ubuntu, Debian, Mint and similar:**
```
sudo apt install ./BeamX-linux-amd64.deb
```
Then open **BeamX** from your app menu.

**Any distribution (portable):**
```
mkdir -p ~/BeamX && tar -xzf BeamX-linux-x64.tar.gz -C ~/BeamX
~/BeamX/beamx
```

Screen sharing and remote control of Linux need an **X11** session. On
Wayland they may not work yet; viewing and controlling other screens works
on both.

## iOS (iPhone / iPad)

Apple only allows apps from outside the App Store through sideloading tools.

1. Install [AltStore](https://altstore.io) or [SideStore](https://sidestore.io)
   by following their guide.
2. Download `BeamX-ios-unsigned.ipa` and open it with AltStore or SideStore.
3. Sign in with your own free Apple ID when asked.

With a free Apple ID, sideloaded apps must be refreshed every 7 days.
AltStore and SideStore can do this automatically.

When BeamX asks to find devices on your local network, tap **Allow**.

**iOS limitations:**
- An iPhone or iPad can **view and control** other screens. Sharing the iPhone's own
  screen isn't available yet.
- Apple does not let any app control an iPhone remotely.
- iPhones can't discover devices automatically. On the other device, tap
  **Pair** and connect by address, or connect from the iPhone by typing the
  other device's IP address.

## Connecting without Wi-Fi

Both devices need to be on the same network, but that network doesn't need a
router or internet:

- **Phone hotspot:** turn on the hotspot on your phone and join it from the
  PC. Open BeamX on both; they find each other automatically.
- **USB cable (Android):** connect the phone to the PC, then on the phone
  turn on **Settings → Network → Hotspot & tethering → USB tethering**.
  Open BeamX on both.

If a device doesn't appear, open **Pair** on it to see its address, then on
the other device tap **Pair → Connect by address** and type it.

## Where received files go

| Device | Folder |
|---|---|
| Windows / macOS / Linux | `Downloads/BeamX` |
| Android | `Download/BeamX` (open with the Files app) |
| iPhone / iPad | Files app → **On My iPhone → BeamX** |

The path of each file is also shown on the **Transfers** screen.
Screenshots (📷) and recordings (⏺) from the stream toolbar are saved in
the same folder. Recording works on Android, iPhone/iPad and Mac.

## Verify your download

Every release file was built by GitHub Actions from this repository's code.

- **Checksum:** compare your file's SHA-256 with `SHA256SUMS.txt` in the release.
  - Windows: `certutil -hashfile BeamX-windows-x64.zip SHA256`
  - macOS / Linux: `shasum -a 256 BeamX-macos.dmg`
- **Build attestation** (needs the [GitHub CLI](https://cli.github.com)):
  ```
  gh attestation verify BeamX-android.apk --repo Rajeev0007/BeamX
  ```
