# OpenVPN Auto-Installer for Ubuntu (Easy-RSA + IPv4 NAT)

This repository provides a simple, opinionated Bash script that installs and configures an **OpenVPN server** on an Ubuntu VPS (22.04 / 24.04).  
It sets up:

- OpenVPN (UDP/1194)
- Easy-RSA PKI (self-hosted CA)
- IPv4-only routing (IPv6 disabled)
- NAT masquerading using iptables
- A ready-to-use client profile (`client1.ovpn`)

The result is a fully working VPN with internet access routed through your VPS.

---

## Features

✔ One-command setup  
✔ Auto-generates server & client certificates (CA, server, client1)  
✔ Inline `.ovpn` file (easy import into OpenVPN apps)  
✔ NAT + forwarding rules automatically configured  
✔ IPv6 disabled to avoid routing leaks  
✔ Works on fresh VPS providers without UFW  

---

## Requirements

- Ubuntu **22.04 or 24.04**
- Root access to a VPS
- A public IPv4 address

---

## Usage

Clone the repo and run the installer:

```bash
git clone https://github.com/yourusername/openvpn-setup.git
cd openvpn-setup
sudo bash setup-openvpn.sh
```


## What the script does

- Installs OpenVPN + Easy-RSA
- Builds a full PKI (CA, server cert, client cert)
- Creates /etc/openvpn/server/server.conf
- Enables IP forwarding & adjusts rp_filter
- Adds correct NAT masquerading rules
- Disables IPv6 to avoid asymmetric routing issues
- Starts the OpenVPN server service


## Uninstall
To remove OpenVPN & networking rules:
```
systemctl stop openvpn-server@server
systemctl disable openvpn-server@server
apt purge -y openvpn easy-rsa
rm -rf /etc/openvpn
netfilter-persistent flush
```
