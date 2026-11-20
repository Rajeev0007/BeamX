#!/usr/bin/env bash
# One-command setup on a fresh Ubuntu server:
#   curl -fsSL https://raw.githubusercontent.com/Rajeev0007/BeamX/main/server/install.sh -o install.sh
#   less install.sh      # read it first
#   sudo bash install.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }

apt-get update -y
apt-get install -y docker.io docker-compose-v2 git openssl curl

dir=/opt/beamx-server
if [[ ! -d "$dir/.git" ]]; then
  git clone --depth 1 https://github.com/Rajeev0007/BeamX.git "$dir"
else
  git -C "$dir" pull --ff-only
fi
cd "$dir/server"

if [[ ! -f .env ]]; then
  ip=$(curl -fsS https://api.ipify.org)
  cat > .env <<ENV
PUBLIC_IP=$ip
DOMAIN=${ip//./-}.sslip.io
TURN_SECRET=$(openssl rand -hex 32)
ENV
fi
source .env

# Open the firewall on the machine itself (cloud firewalls are separate).
if command -v ufw >/dev/null && ufw status | grep -q active; then
  ufw allow 80/tcp; ufw allow 443/tcp; ufw allow 3478; ufw allow 49160:49200/udp
fi
iptables -C INPUT -p tcp -m multiport --dports 80,443,3478 -j ACCEPT 2>/dev/null ||
  iptables -I INPUT -p tcp -m multiport --dports 80,443,3478 -j ACCEPT
iptables -C INPUT -p udp -m multiport --dports 3478,49160:49200 -j ACCEPT 2>/dev/null ||
  iptables -I INPUT -p udp -m multiport --dports 3478,49160:49200 -j ACCEPT

docker compose up -d --build
echo
echo "Done. In BeamX → Settings → Internet server, enter:"
echo "  wss://$DOMAIN/beamx"
echo "Check it works: https://$DOMAIN/health"
