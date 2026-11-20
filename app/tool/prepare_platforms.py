#!/usr/bin/env python3
"""Generate native platform folders and apply BeamX settings.

Runs `flutter create` (which only adds missing files and never touches
lib/), then patches app names, permissions and entitlements. Safe to run
repeatedly. Usage: python3 tool/prepare_platforms.py [platform ...]
"""
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ALL = ["android", "ios", "macos", "windows", "linux"]


def patch(path: pathlib.Path, fn) -> None:
    if not path.exists():
        return
    old = path.read_text(encoding="utf-8")
    new = fn(old)
    if new != old:
        path.write_text(new, encoding="utf-8")
        print(f"patched {path.relative_to(ROOT)}")


def android(s: str) -> str:
    perms = [
        "android.permission.INTERNET",
        "android.permission.ACCESS_NETWORK_STATE",
        "android.permission.ACCESS_WIFI_STATE",
        "android.permission.CHANGE_WIFI_MULTICAST_STATE",
        # Screen sharing runs in a foreground service (Android 14+ rules).
        "android.permission.FOREGROUND_SERVICE",
        "android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION",
        "android.permission.POST_NOTIFICATIONS",
        "android.permission.WAKE_LOCK",
        "android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
    ]
    for p in perms:
        if f'"{p}"' not in s:
            s = s.replace(
                "<application", f'<uses-permission android:name="{p}"/>\n    <application', 1
            )
    a11y = ".BeamXAccessibilityService"
    if a11y not in s:
        s = s.replace(
            "</application>",
            f'    <service android:name="{a11y}"\n'
            '            android:label="@string/beamx_accessibility_label"\n'
            '            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE"\n'
            '            android:exported="true">\n'
            "            <intent-filter>\n"
            '                <action android:name="android.accessibilityservice.AccessibilityService" />\n'
            "            </intent-filter>\n"
            '            <meta-data android:name="android.accessibilityservice"\n'
            '                android:resource="@xml/beamx_accessibility" />\n'
            "        </service>\n"
            "    </application>",
            1,
        )
    service = "de.julianassmann.flutter_background.IsolateHolderService"
    if service not in s:
        s = s.replace(
            "</application>",
            f'    <service android:name="{service}"\n'
            '            android:enabled="true"\n'
            '            android:exported="false"\n'
            '            android:foregroundServiceType="mediaProjection" />\n'
            "    </application>",
            1,
        )
    return re.sub(r'android:label="[^"]*"', 'android:label="BeamX"', s, count=1)


PLIST_TEXT = {
    "NSLocalNetworkUsageDescription":
        "BeamX finds and connects to your other devices on this network.",
    # Required by the WebRTC library even though BeamX only captures the screen.
    "NSCameraUsageDescription":
        "BeamX uses the camera only to scan pairing QR codes.",
    "NSMicrophoneUsageDescription":
        "BeamX does not use the microphone yet. This is required by the audio library.",
}


def add_plist_keys(s: str) -> str:
    for key, text in PLIST_TEXT.items():
        if f"<key>{key}</key>" not in s:
            s = s.replace(
                "<dict>", f"<dict>\n\t<key>{key}</key>\n\t<string>{text}</string>", 1
            )
    return s


def ios_plist(s: str) -> str:
    s = re.sub(
        r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)", r"\1BeamX\2", s
    )
    # Received files appear in the Files app under "On My iPhone → BeamX".
    for key in ("UIFileSharingEnabled", "LSSupportsOpeningDocumentsInPlace"):
        if f"<key>{key}</key>" not in s:
            s = s.replace("<dict>", f"<dict>\n\t<key>{key}</key>\n\t<true/>", 1)
    return add_plist_keys(s)


def copy_android_native() -> None:
    """Copies BeamX's Kotlin code and resources into the Android project."""
    src = ROOT / "native/android"
    main = ROOT / "android/app/src/main"
    if not main.exists():
        return
    for old in list(main.rglob("MainActivity.kt")) + list(main.rglob("MainActivity.java")):
        old.unlink()
    pkg = main / "kotlin/io/github/rajeev0007/beamx"
    pkg.mkdir(parents=True, exist_ok=True)
    for f in (src / "kotlin").iterdir():
        shutil.copy(f, pkg / f.name)
    for sub in ("xml", "values"):
        (main / "res" / sub).mkdir(parents=True, exist_ok=True)
        for f in (src / "res" / sub).iterdir():
            shutil.copy(f, main / "res" / sub / f.name)
    print("copied Android native code")


def mac_entitlements(s: str) -> str:
    # Controlling the Mac (posting input events) is not possible inside the
    # App Sandbox. BeamX is distributed outside the App Store, so it runs
    # unsandboxed like other remote desktop apps.
    s = re.sub(
        r"(<key>com\.apple\.security\.app-sandbox</key>\s*)<true/>", r"\1<false/>", s
    )
    for key in (
        "com.apple.security.network.server",
        "com.apple.security.network.client",
        "com.apple.security.device.camera",
        "com.apple.security.files.user-selected.read-only",
        "com.apple.security.files.downloads.read-write",
    ):
        if key not in s:
            s = s.replace("<dict>", f"<dict>\n\t<key>{key}</key>\n\t<true/>", 1)
    return s


def mac_name(s: str) -> str:
    return re.sub(r"PRODUCT_NAME = .*", "PRODUCT_NAME = BeamX", s)


def win_name(s: str) -> str:
    return s.replace('L"beamx"', 'L"BeamX"')


def linux_name(s: str) -> str:
    return s.replace('"beamx"', '"BeamX"')


def main() -> None:
    platforms = sys.argv[1:] or ALL
    flutter = "flutter.bat" if sys.platform == "win32" else "flutter"
    subprocess.run(
        [flutter, "create", "--org", "io.github.rajeev0007",
         "--project-name", "beamx", "--platforms", ",".join(platforms), "."],
        cwd=ROOT, check=True,
    )
    patch(ROOT / "android/app/src/main/AndroidManifest.xml", android)
    copy_android_native()
    patch(ROOT / "ios/Runner/Info.plist", ios_plist)
    for f in ("DebugProfile.entitlements", "Release.entitlements"):
        patch(ROOT / "macos/Runner" / f, mac_entitlements)
    patch(ROOT / "macos/Runner/Configs/AppInfo.xcconfig", mac_name)
    patch(ROOT / "macos/Runner/Info.plist", add_plist_keys)
    patch(ROOT / "windows/runner/main.cpp", win_name)
    patch(ROOT / "linux/runner/my_application.cc", linux_name)
    # flutter create adds a sample widget test we don't use.
    sample = ROOT / "test/widget_test.dart"
    if sample.exists():
        sample.unlink()


if __name__ == "__main__":
    main()
