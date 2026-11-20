#!/usr/bin/env python3
"""Generate native platform folders and apply BeamX settings.

Runs `flutter create` (which only adds missing files and never touches
lib/), then patches app names, permissions and entitlements. Safe to run
repeatedly. Usage: python3 tool/prepare_platforms.py [platform ...]
"""
import pathlib
import re
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
    ]
    for p in perms:
        if p not in s:
            s = s.replace(
                "<application", f'<uses-permission android:name="{p}"/>\n    <application', 1
            )
    return re.sub(r'android:label="[^"]*"', 'android:label="BeamX"', s, count=1)


def ios_plist(s: str) -> str:
    s = re.sub(
        r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)", r"\1BeamX\2", s
    )
    if "NSLocalNetworkUsageDescription" not in s:
        s = s.replace(
            "<dict>",
            "<dict>\n\t<key>NSLocalNetworkUsageDescription</key>\n"
            "\t<string>BeamX finds and connects to your other devices on this network.</string>",
            1,
        )
    return s


def mac_entitlements(s: str) -> str:
    for key in ("com.apple.security.network.server", "com.apple.security.network.client"):
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
    patch(ROOT / "ios/Runner/Info.plist", ios_plist)
    for f in ("DebugProfile.entitlements", "Release.entitlements"):
        patch(ROOT / "macos/Runner" / f, mac_entitlements)
    patch(ROOT / "macos/Runner/Configs/AppInfo.xcconfig", mac_name)
    patch(ROOT / "windows/runner/main.cpp", win_name)
    patch(ROOT / "linux/runner/my_application.cc", linux_name)
    # flutter create adds a sample widget test we don't use.
    sample = ROOT / "test/widget_test.dart"
    if sample.exists():
        sample.unlink()


if __name__ == "__main__":
    main()
