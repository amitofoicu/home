#!/bin/bash
set -e

echo "=================================================="
echo "  WireGuard Server One-Click Installation + 300s Auto Shutdown"
echo "=================================================="
echo ""

###############################################
# Detect network interface
###############################################
IFACE=$(ip route get 8.8.8.8 | awk -- '{print $5; exit}')
echo "Detected network interface: $IFACE"

###############################################
# Install WireGuard and related tools
###############################################
apt update
apt install -y wireguard net-tools

###############################################
# Enable IP forwarding
###############################################
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

###############################################
# Fixed key pairs (using provided keys)
###############################################
SERVER_PRIV="cDx7g/B77vfohzopZrDCD2QOsowxrbTzi5k3D9dGXV8="
SERVER_PUB="+tD1Ok8m85VI30jaHvAP9TsmWoKFBzNWNca9t5v9SiQ="

CLIENT1_PRIV="GAnR28Ee3O/hwoERyCSXWjBKzq8z7DIW3ZCr1Opau0Q="
CLIENT1_PUB="tdpAAwY2NuY4lm6OG3Wq6Qr6zSJm6Bwd4HFcUhS0GXc="

CLIENT2_PRIV="WPGxp47vsDJR+kNOEWUWQaefnr2K6Y2LtMCl5kfMEmc="
CLIENT2_PUB="n1tqZOpwvHWmQK5/kFpj+mG7VeqNXoy0mLby48saszI="

CLIENT3_PRIV="4Bv2xK9pLm8qR5sT7wY3zN6cE1aJ4dF2gH5iK8oM9pQ="
CLIENT3_PUB="qR8sT2wY4uI6oP9aL1kD3fG5hJ7kL9zX1cV3bN5mQ7wE="

CLIENT4_PRIV="7yU5iK9oL2pM6qR8sT4wY7zN1cE3aJ5dF8gH0jK2lM4="
CLIENT4_PUB="nP6qR9sT2wY5uI8oP1aL4kD7fG0hJ3kL6mN9pQ2sT5w="

###############################################
# Get EC2 public IP
###############################################
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || curl -s ifconfig.me)
echo "Server public IP: $PUBLIC_IP"

###############################################
# Create WireGuard configuration file
###############################################
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = $SERVER_PRIV

# NAT client traffic
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

# Client 3
[Peer]
PublicKey = $CLIENT3_PUB
AllowedIPs = 10.0.0.4/32

# Client 4
[Peer]
PublicKey = $CLIENT4_PUB
AllowedIPs = 10.0.0.5/32
EOF

chmod 600 /etc/wireguard/wg0.conf

###############################################
# Create client configuration files (no keepalive)
###############################################
# Client 1
cat > /root/client1.conf <<EOF
[Interface]
PrivateKey = $CLIENT1_PRIV
Address = 10.0.0.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $PUBLIC_IP:51820
AllowedIPs = 0.0.0.0/0
# Note: No PersistentKeepalive configured - no keepalive
EOF

# Client 2
cat > /root/client2.conf <<EOF
[Interface]
PrivateKey = $CLIENT2_PRIV
Address = 10.0.0.3/24
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $PUBLIC_IP:51820
AllowedIPs = 0.0.0.0/0
# Note: No PersistentKeepalive configured - no keepalive
EOF

# Client 3
cat > /root/client3.conf <<EOF
[Interface]
PrivateKey = $CLIENT3_PRIV
Address = 10.0.0.4/24
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $PUBLIC_IP:51820
AllowedIPs = 0.0.0.0/0
# Note: No PersistentKeepalive configured - no keepalive
EOF

# Client 4
cat > /root/client4.conf <<EOF
[Interface]
PrivateKey = $CLIENT4_PRIV
Address = 10.0.0.5/24
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $PUBLIC_IP:51820
AllowedIPs = 0.0.0.0/0
# Note: No PersistentKeepalive configured - no keepalive
EOF

chmod 600 /root/client*.conf

###############################################
# Start WireGuard
###############################################
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

###############################################
# Create 300-second auto-shutdown monitoring script (for no-keepalive environment)
###############################################
cat > /usr/local/bin/wg-auto-shutdown.sh <<'EOF'
#!/bin/bash
# ================================================
# WireGuard auto-shutdown monitoring script for no-keepalive environment
# Function: Automatically shutdown when all peers are inactive for over 300 seconds
# Threshold: 300 seconds (5 minutes) - covers kernel 275s timeout period
# Check interval: 60 seconds
# ================================================

WG_INTERFACE="wg0"
IDLE_THRESHOLD=300
CHECK_INTERVAL=60
STATE_FILE="/var/run/wg-auto-shutdown.state"

# Color output (terminal only)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; NC=''
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_info() {
    log "${GREEN}INFO${NC} $1"
}

log_warn() {
    log "${YELLOW}WARN${NC} $1"
}

log_error() {
    log "${RED}ERROR${NC} $1"
}

# Initialize state file
echo "0" > "$STATE_FILE"
log_info "WireGuard auto-shutdown monitoring started"
log_info "Monitoring interface: $WG_INTERFACE"
log_info "Idle threshold: ${IDLE_THRESHOLD} seconds (no-keepalive environment)"
log_info "Check interval: ${CHECK_INTERVAL} seconds"
log_info "State file: $STATE_FILE"

while true; do
    # 1. Check WireGuard interface status
    if ! ip link show "$WG_INTERFACE" >/dev/null 2>&1; then
        log_warn "Interface $WG_INTERFACE does not exist, waiting..."
        sleep $CHECK_INTERVAL
        continue
    fi
    
    if ! systemctl is-active --quiet wg-quick@wg0; then
        log_warn "WireGuard service is not running"
        sleep $CHECK_INTERVAL
        continue
    fi
    
    # 2. Get current timestamp
    NOW=$(date +%s)
    
    # 3. Analyze handshake times for all peers
    ACTIVE_COUNT=0
    MAX_IDLE=0
    VALID_PEERS=0
    TOTAL_PEERS=0
    
    while read -r line; do
        [ -z "$line" ] && continue
        
        TOTAL_PEERS=$((TOTAL_PEERS + 1))
        PEER_KEY=$(echo "$line" | awk '{print $1}')
        TIMESTAMP=$(echo "$line" | awk '{print $2}')
        
        # Filter invalid timestamps (peers that never handshaked)
        if ! [[ "$TIMESTAMP" =~ ^[0-9]+$ ]] || [ "$TIMESTAMP" -eq 0 ]; then
            continue
        fi
        
        VALID_PEERS=$((VALID_PEERS + 1))
        IDLE_SECONDS=$((NOW - TIMESTAMP))
        
        # Update maximum idle time
        if [ $IDLE_SECONDS -gt $MAX_IDLE ]; then
            MAX_IDLE=$IDLE_SECONDS
        fi
        
        # Determine if peer is active (idle time < threshold)
        if [ $IDLE_SECONDS -lt $IDLE_THRESHOLD ]; then
            ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
            log_info "Active peer: ${PEER_KEY:0:8}... Idle: ${IDLE_SECONDS}s"
        fi
    done < <(wg show "$WG_INTERFACE" latest-handshakes 2>/dev/null || true)
    
    # 4. Record current maximum idle time
    echo "$MAX_IDLE" > "$STATE_FILE"
    
    # 5. Status report
    if [ $VALID_PEERS -eq 0 ]; then
        log_info "No valid peer configurations or never had handshake"
    else
        log_info "Status report - Active peers: ${ACTIVE_COUNT}/${VALID_PEERS}, Maximum idle: ${MAX_IDLE}s"
        
        # 6. Decision: Are all peers idle beyond threshold?
        if [ $ACTIVE_COUNT -eq 0 ] && [ $VALID_PEERS -gt 0 ]; then
            log_warn "All peers idle beyond threshold! Maximum idle: ${MAX_IDLE}s (threshold: ${IDLE_THRESHOLD}s)"
            
            # Read previous maximum idle time
            PREV_IDLE=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
            
            # Need two consecutive detections of timeout to prevent false positives
            if [ $MAX_IDLE -ge $IDLE_THRESHOLD ] && [ $PREV_IDLE -ge $IDLE_THRESHOLD ]; then
                log_warn "Two consecutive detections with no active peers, will shutdown in 60 seconds"
                
                # Wait 60 seconds, giving clients chance to reconnect
                sleep 60
                
                # Final confirmation
                FINAL_NOW=$(date +%s)
                FINAL_ACTIVE=0
                
                while read -r line; do
                    [ -z "$line" ] && continue
                    TIMESTAMP=$(echo "$line" | awk '{print $2}')
                    if [[ "$TIMESTAMP" =~ ^[0-9]+$ ]] && [ "$TIMESTAMP" -ne 0 ]; then
                        IDLE=$((FINAL_NOW - TIMESTAMP))
                        if [ $IDLE -lt $IDLE_THRESHOLD ]; then
                            FINAL_ACTIVE=1
                            break
                        fi
                    fi
                done < <(wg show "$WG_INTERFACE" latest-handshakes 2>/dev/null || true)
                
                # Execute shutdown
                if [ $FINAL_ACTIVE -eq 0 ]; then
                    log_error "Final confirmation: Still no active peers, executing shutdown!"
                    sync
                    sync
                    sleep 2
                    shutdown -h now
                    exit 0
                else
                    log_info "Final confirmation: Active peer detected, canceling shutdown"
                    # Reset state
                    echo "0" > "$STATE_FILE"
                fi
            else
                log_info "First detection of no active peers, waiting for next confirmation"
            fi
        fi
    fi
    
    sleep $CHECK_INTERVAL
done
EOF

chmod +x /usr/local/bin/wg-auto-shutdown.sh

###############################################
# Create Systemd service
###############################################
cat > /etc/systemd/system/wg-auto-shutdown.service <<EOF
[Unit]
Description=WireGuard Auto Shutdown Monitor (300s idle timeout)
After=network.target wg-quick@wg0.service
Requires=wg-quick@wg0.service
Documentation=https://www.wireguard.com/

[Service]
Type=simple
ExecStart=/usr/local/bin/wg-auto-shutdown.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

###############################################
# Stop old services, enable new service
###############################################
systemctl daemon-reload

# Stop and disable all potentially conflicting monitoring services
for old in wg-monitor wg-ping-monitor wg-conntrack-monitor wg-idle-shutdown; do
    systemctl stop ${old}.service 2>/dev/null || true
    systemctl disable ${old}.service 2>/dev/null || true
done

# Enable new service
systemctl enable wg-auto-shutdown.service
systemctl restart wg-auto-shutdown.service

###############################################
# Configure log rotation (prevent excessive logs)
###############################################
cat > /etc/logrotate.d/wg-auto-shutdown <<EOF
/var/log/wg-auto-shutdown.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
}
EOF

###############################################
# Completion information
###############################################
clear
cat << "EOF"

==========================================================
     WireGuard installation complete + 300s auto shutdown enabled
==========================================================

EOF

echo ""
echo "Server Information:"
echo "   - Public IP: $PUBLIC_IP"
echo "   - WireGuard port: 51820"
echo "   - Virtual network: 10.0.0.0/24"
echo "   - Server virtual IP: 10.0.0.1"
echo ""
echo "Client Configuration Files:"
echo "   - Client 1: /root/client1.conf (IP: 10.0.0.2)"
echo "   - Client 2: /root/client2.conf (IP: 10.0.0.3)"
echo "   - Client 3: /root/client3.conf (IP: 10.0.0.4)"
echo "   - Client 4: /root/client4.conf (IP: 10.0.0.5)"
echo ""
echo "Key Information:"
echo "   - Server public key: $SERVER_PUB"
echo "   - Client 1 public key: $CLIENT1_PUB"
echo "   - Client 2 public key: $CLIENT2_PUB"
echo "   - Client 3 public key: $CLIENT3_PUB"
echo "   - Client 4 public key: $CLIENT4_PUB"
echo ""
echo "Auto Shutdown Configuration:"
echo "   - Detection method: WireGuard handshake timestamps"
echo "   - Idle threshold: 300 seconds (5 minutes)"
echo "   - Check interval: 60 seconds"
echo "   - Double confirmation: Enabled"
echo "   - Client keepalive: Not enabled (no keepalive)"
echo "   - Shutdown condition: All peers idle for over 300 seconds"
echo "   - Actual shutdown time: Approximately 360 seconds after last handshake"
echo ""
echo "Service Management Commands:"
echo "   - Check status: systemctl status wg-auto-shutdown"
echo "   - Real-time logs: journalctl -u wg-auto-shutdown -f"
echo "   - Restart monitoring: systemctl restart wg-auto-shutdown"
echo "   - Stop monitoring: systemctl stop wg-auto-shutdown"
echo ""
echo "WireGuard Management Commands:"
echo "   - View status: wg show"
echo "   - Restart service: systemctl restart wg-quick@wg0"
echo "   - Stop service: systemctl stop wg-quick@wg0"
echo ""
echo "Quick Test:"
echo "   - View handshake status: wg show wg0 latest-handshakes"
echo "   - Monitor logs: journalctl -u wg-auto-shutdown -f --since '1 minute ago'"
echo ""
echo "Important Notes:"
echo "   - Currently in [no-keepalive] mode, shutdown delay approximately 6 minutes"
echo "   - For 1-minute shutdown, add to clients: PersistentKeepalive = 10"
echo "   - Modify threshold: Edit IDLE_THRESHOLD in /usr/local/bin/wg-auto-shutdown.sh"
echo ""
echo "=================================================="
echo "Installation complete! Monitoring service started"
echo "=================================================="

# Display current service status
sleep 2
systemctl status wg-auto-shutdown.service --no-pager -l