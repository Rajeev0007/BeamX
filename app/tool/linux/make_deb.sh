#!/usr/bin/env bash
# Packages the Linux release bundle as a .deb. Usage: make_deb.sh <out.deb>
set -euo pipefail
out="$1"
version="0.0.0~dev"
if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  version="${GITHUB_REF_NAME#v}"
  version="${version/-/\~}"   # 0.6.0-preview -> 0.6.0~preview (sorts before 0.6.0)
fi
pkg="$(mktemp -d)"
mkdir -p "$pkg/DEBIAN" "$pkg/opt/beamx" "$pkg/usr/bin" "$pkg/usr/share/applications"
cp -r build/linux/x64/release/bundle/. "$pkg/opt/beamx/"
ln -s /opt/beamx/beamx "$pkg/usr/bin/beamx"
cat > "$pkg/DEBIAN/control" <<CONTROL
Package: beamx
Version: $version
Architecture: amd64
Maintainer: Rajeev0007 <Rajeev0007@users.noreply.github.com>
Homepage: https://github.com/Rajeev0007/BeamX
Depends: libgtk-3-0 | libgtk-3-0t64, libpulse0, libxtst6
Section: net
Priority: optional
Description: Screen sharing and remote control between your devices
 BeamX shares screens, sound, files and clipboard, and lets you control
 devices, between Windows, macOS, Linux, Android and iOS.
CONTROL
cat > "$pkg/usr/share/applications/beamx.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=BeamX
Comment=Screen sharing and remote control
Exec=/opt/beamx/beamx
Terminal=false
Categories=Network;RemoteAccess;
DESKTOP
dpkg-deb --build --root-owner-group "$pkg" "$out"
rm -rf "$pkg"
