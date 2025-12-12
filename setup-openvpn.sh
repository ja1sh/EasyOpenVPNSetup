#!/usr/bin/env bash
# Simple OpenVPN + Easy-RSA setup for Ubuntu VPS
# Opinionated: IPv4-only, UDP/1194, one client profile.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "[-] This script must be run as root." >&2
  exit 1
fi

DEFAULT_CLIENT_NAME="client1"

read -rp "Enter VPN client name [${DEFAULT_CLIENT_NAME}]: " CLIENT_NAME
CLIENT_NAME=${CLIENT_NAME:-$DEFAULT_CLIENT_NAME}

SERVER_IP_DEFAULT=$(curl -4 -s https://ifconfig.me || echo "YOUR_SERVER_IP")
read -rp "Enter public IP for this VPS [${SERVER_IP_DEFAULT}]: " SERVER_IP
SERVER_IP=${SERVER_IP:-$SERVER_IP_DEFAULT}

echo "[+] Installing packages..."
apt update
apt install -y openvpn easy-rsa iptables-persistent curl

EASYRSA_DIR="/etc/openvpn/easy-rsa"
SERVER_DIR="/etc/openvpn/server"
mkdir -p "$EASYRSA_DIR" "$SERVER_DIR"

echo "[+] Setting up Easy-RSA PKI..."
cp -r /usr/share/easy-rsa/* "$EASYRSA_DIR"
cd "$EASYRSA_DIR"

./easyrsa init-pki

export EASYRSA_BATCH=1
./easyrsa build-ca nopass
./easyrsa gen-req server nopass
./easyrsa sign-req server server
./easyrsa gen-dh

echo "[+] Generating tls-auth key..."
openvpn --genkey --secret "${SERVER_DIR}/ta.key"

echo "[+] Copying server certs/keys..."
cp pki/ca.crt "${SERVER_DIR}/"
cp pki/issued/server.crt "${SERVER_DIR}/"
cp pki/private/server.key "${SERVER_DIR}/"
cp pki/dh.pem "${SERVER_DIR}/"

echo "[+] Writing OpenVPN server config..."
cat >"${SERVER_DIR}/server.conf" << 'EOF'
port 1194
proto udp
dev tun

ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-auth ta.key 0

topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt

push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 8.8.8.8"

keepalive 10 120
cipher AES-256-GCM
user nobody
group nogroup
persist-key
persist-tun

status /var/log/openvpn-status.log
log-append /var/log/openvpn.log
verb 3
EOF

echo "[+] Enabling IPv4 forwarding, relaxing rp_filter, disabling IPv6..."
cat >/etc/sysctl.d/99-openvpn.conf << 'EOF'
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0

net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

sysctl --system

WAN_IFACE=$(ip route | awk '/default/ {print $5; exit}')
if [[ -z "${WAN_IFACE}" ]]; then
  echo "[-] Could not determine WAN interface from 'ip route'." >&2
  exit 1
fi
echo "[+] Detected WAN interface: ${WAN_IFACE}"

echo "[+] Configuring iptables NAT and FORWARD rules..."
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "${WAN_IFACE}" -j MASQUERADE
iptables -I FORWARD 1 -i tun0 -o "${WAN_IFACE}" -j ACCEPT
iptables -I FORWARD 1 -i "${WAN_IFACE}" -o tun0 -j ACCEPT

netfilter-persistent save

echo "[+] Creating client cert/key: ${CLIENT_NAME}..."
cd "$EASYRSA_DIR"
./easyrsa gen-req "${CLIENT_NAME}" nopass
./easyrsa sign-req client "${CLIENT_NAME}"

CLIENT_OVPN="/root/${CLIENT_NAME}.ovpn"
echo "[+] Generating client profile at ${CLIENT_OVPN} ..."

cat >"${CLIENT_OVPN}" <<EOF
client
dev tun
proto udp
remote ${SERVER_IP} 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
key-direction 1
verb 3

<ca>
$(cat pki/ca.crt)
</ca>

<cert>
$(cat pki/issued/${CLIENT_NAME}.crt)
</cert>

<key>
$(cat pki/private/${CLIENT_NAME}.key)
</key>

<tls-auth>
$(cat ${SERVER_DIR}/ta.key)
</tls-auth>
EOF

echo "[+] Enabling and starting OpenVPN server..."
systemctl enable --now openvpn-server@server

echo
echo "=================================================="
echo "[+] OpenVPN setup complete."
echo "[+] Client config: ${CLIENT_OVPN}"
echo "[+] Copy this .ovpn file to your device and import it."
echo "=================================================="
