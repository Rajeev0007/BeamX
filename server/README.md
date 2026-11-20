# BeamX internet server

Lets BeamX devices connect from anywhere, not just on the same Wi-Fi.

**What it does:** devices stay connected to it so others can ring them by
their 9-digit **Internet ID**. It passes the short setup messages between two
devices, and its TURN relay carries the encrypted stream when the two
networks block a direct connection (common on mobile data).

**What it can't do:** see or change your screen, sound, files or typing.
Everything is end-to-end encrypted between the two devices, and the setup
messages are authenticated with the pairing code or trust key, which the
server never learns.

It's one Node.js file with no dependencies (`beamx-signal.mjs`), plus
[coturn](https://github.com/coturn/coturn) for TURN and
[Caddy](https://caddyserver.com) for automatic HTTPS.

---

## Option 1: free cloud server (recommended, works 24/7)

Any small Linux server with a public IP works. **Oracle Cloud Always Free**
is one option with a generous free tier.

### 1. Create the server
1. Sign up at <https://www.oracle.com/cloud/free/>. A card is needed for
   identity verification; Always Free resources aren't charged.
2. **Compute → Instances → Create instance.**
   - Image: **Ubuntu 24.04** (or newer)
   - Shape: any **Always Free eligible** shape
   - Download the SSH key it offers.
3. Open the instance and note its **Public IP address**.

### 2. Open the ports in the cloud firewall
**Instance → Subnet → Default Security List → Add Ingress Rules**, source
`0.0.0.0/0`:

| Protocol | Port(s) | Used for |
|---|---|---|
| TCP | 80, 443 | HTTPS certificate and secure connection |
| TCP + UDP | 3478 | TURN |
| UDP | 49160-49200 | TURN media |

### 3. Install
Connect with SSH (`ssh -i your-key ubuntu@YOUR_IP`), then:
```
curl -fsSL https://raw.githubusercontent.com/Rajeev0007/BeamX/main/server/install.sh -o install.sh
less install.sh        # read what it does first
sudo bash install.sh
```
It installs Docker, creates a random TURN secret, gets a free HTTPS
certificate for `YOUR-IP-WITH-DASHES.sslip.io`, and starts everything. At
the end it prints your server address, for example:
```
wss://203-0-113-5.sslip.io/beamx
```

### 4. Check it
Open `https://203-0-113-5.sslip.io/health` in a browser. It should say
`ok 0 devices online`.

---

## Option 2: your own PC (free, only works while the PC is on)

Needs a Linux PC or WSL2 on Windows, and a router where you can forward ports.

1. Install Docker: <https://docs.docker.com/engine/install/>.
2. In your router, forward TCP 80, 443, TCP+UDP 3478 and UDP 49160-49200 to
   this PC.
3. Find your public IP at <https://api.ipify.org>.
4. Run:
   ```
   git clone https://github.com/Rajeev0007/BeamX.git
   cd BeamX/server
   cp .env.example .env     # then edit: PUBLIC_IP, DOMAIN, TURN_SECRET
   docker compose up -d --build
   ```
   Set `DOMAIN` to your IP with dashes plus `.sslip.io`, and `TURN_SECRET`
   to the output of `openssl rand -hex 32`.

Home internet IPs can change. If it stops working, update `.env` and run
`docker compose up -d` again.

---

## Use it in BeamX

On **every** device: **Settings → Connection → Internet server**, enter the
address (`wss://…/beamx`) and press Enter. The Devices screen then shows the
device's **Internet ID**.

To connect: on one device tap **Pair → Over the internet**, type the other
device's Internet ID, then its pairing code. Tick **Trust this device** when
allowing, and next time it shows under **Your trusted devices · over the
internet** for one-tap connecting.

## Updating
```
cd /opt/beamx-server && sudo git pull && cd server && sudo docker compose up -d --build
```

## Security notes
- Device IDs are claimed with a secret key on first use, so another device
  can't take over your Internet ID.
- Rate limits: 200 messages/second and 4 sessions per device, 20
  connections per IP address, 64 KB per message.
- TURN credentials expire after 12 hours, and coturn refuses to relay to
  private network addresses, so the server can't be used to reach machines
  on its own network.
- The server stores only device IDs and hashed keys
  (`data/registrations.json`). It keeps no logs of who connected to whom.

## Running the tests
```
node --test server/test.mjs
```
