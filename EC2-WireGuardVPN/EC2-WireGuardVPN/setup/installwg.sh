#!/bin/bash
set -e

echo "=== Installing WireGuard Server on Debian ==="

###############################################
# Detect primary network interface (ens5/eth0)
###############################################
IFACE=$(ip route get 8.8.8.8 | awk -- '{print $5; exit}')
echo "Detected network interface: $IFACE"

###############################################
# Install WireGuard
###############################################
apt update
apt install -y wireguard
###############################################
# Enable ipv4 forwarding
sudo sysctl -w net.ipv4.ip_forward=1
###############################################
# Use fixed keys provided by the user
###############################################
SERVER_PRIV="cDx7g/B77vfohzopZrDCD2QOsowxrbTzi5k3D9dGXV8="
SERVER_PUB="+tD1Ok8m85VI30jaHvAP9TsmWoKFBzNWNca9t5v9SiQ="

CLIENT1_PRIV="GAnR28Ee3O/hwoERyCSXWjBKzq8z7DIW3ZCr1Opau0Q="
CLIENT1_PUB="tdpAAwY2NuY4lm6OG3Wq6Qr6zSJm6Bwd4HFcUhS0GXc="

CLIENT2_PRIV="WPGxp47vsDJR+kNOEWUWQaefnr2K6Y2LtMCl5kfMEmc="
CLIENT2_PUB="n1tqZOpwvHWmQK5/kFpj+mG7VeqNXoy0mLby48saszI="

###############################################
# Determine EC2 public IP
###############################################
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "EC2 Public IP = $PUBLIC_IP"

###############################################
# Write the WireGuard server config
###############################################
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = $SERVER_PRIV

# NAT all client traffic
PostUp   = iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp   = iptables -A FORWARD -o wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o $IFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -D FORWARD -o wg0 -j ACCEPT

# Client 1
[Peer]
PublicKey = $CLIENT1_PUB
AllowedIPs = 10.0.0.2/32

# Client 2
[Peer]
PublicKey = $CLIENT2_PUB
AllowedIPs = 10.0.0.3/32
EOF

chmod 600 /etc/wireguard/wg0.conf

###############################################
# Create Client 1 config
###############################################
cat > /root/client1.conf <<EOF
[Interface]
PrivateKey = $CLIENT1_PRIV
Address = 10.0.0.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $PUBLIC_IP:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

###############################################
# Create Client 2 config
###############################################
cat > /root/client2.conf <<EOF
[Interface]
PrivateKey = $CLIENT2_PRIV
Address = 10.0.0.3/24
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $PUBLIC_IP:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

chmod 600 /root/client*.conf

###############################################
# Start and enable WireGuard
###############################################
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

echo ""
echo "=================================================="
echo " WireGuard Installed & Running"
echo " Server public IP: $PUBLIC_IP"
echo " Client configs created:"
echo "   /root/client1.conf"
echo "   /root/client2.conf"
echo "=================================================="
echo ""