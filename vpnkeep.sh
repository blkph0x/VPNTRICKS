#!/bin/bash

# Script to maintain VPN connection on wlan0 while connected to internal network via eth0

# Function to get IP address of an interface
get_ip() {
  local interface="$1"
  ip -o -4 addr show dev "$interface" | awk '{print $4}' | cut -d/ -f1
}

# Function to get default gateway of an interface
get_gateway() {
  local interface="$1"
  ip route show dev "$interface" | grep default | awk '{print $3}'
}

# Get VPN configuration path from user
read -p "Enter path to your VPN configuration file: " VPN_CONFIG_PATH

# Connect to VPN
echo "Connecting to VPN over wlan0..."
if ! sudo openvpn --config "$VPN_CONFIG_PATH" --daemon; then
  echo "Failed to establish VPN connection. Please check your configuration."
  exit 1
fi

# Wait for VPN to establish
echo "Waiting for VPN to establish..."
sleep 10  # Adjust sleep time if necessary

# Retrieve IP addresses and gateways
VPN_INTERFACE="tun0"
WLAN_INTERFACE="wlan0"
ETH_INTERFACE="eth0"

VPN_IP=$(get_ip "$VPN_INTERFACE")
WLAN_IP=$(get_ip "$WLAN_INTERFACE")
WLAN_GATEWAY=$(get_gateway "$WLAN_INTERFACE")

if [[ -z "$VPN_IP" || -z "$WLAN_IP" || -z "$WLAN_GATEWAY" ]]; then
  echo "Failed to retrieve necessary network information."
  exit 1
fi

# Configure routing rules
echo "Configuring routing rules..."
sudo ip rule add from "$VPN_IP" table 100 || {
  echo "Failed to add routing rule. Check system logs for details."
  exit 1
}
sudo ip route add default via "$WLAN_GATEWAY" dev "$WLAN_INTERFACE" table 100 || {
  echo "Failed to add default route. Check system logs for details."
  exit 1
}

# Bind SSH server to VPN IP (optional)
read -p "Bind SSH server to VPN IP address? (y/N): " BIND_SSH
if [[ "$BIND_SSH" =~ ^[Yy]$ ]]; then
  echo "Binding SSH server to VPN IP address..."
  sudo sed -i '/^ListenAddress/d' /etc/ssh/sshd_config
  echo "ListenAddress $VPN_IP" | sudo tee -a /etc/ssh/sshd_config
  sudo systemctl restart sshd
fi

# Setup persistent routing
echo "Setting up persistent routing..."
PERSISTENT_ROUTE_SCRIPT="/etc/network/if-up.d/vpn-routing"

sudo tee "$PERSISTENT_ROUTE_SCRIPT" > /dev/null <<EOL
#!/bin/bash
ip rule add from $VPN_IP table 100
ip route add default via $WLAN_GATEWAY dev $WLAN_INTERFACE table 100
EOL

sudo chmod +x "$PERSISTENT_ROUTE_SCRIPT"

# Instruction to connect Ethernet cable
echo "Please connect the Ethernet cable now."
read -p "Press Enter after connecting the Ethernet cable..."

# Verify setup
echo "Verifying setup..."
VPN_IP_AFTER=$(get_ip "$VPN_INTERFACE")
if [[ "$VPN_IP" == "$VPN_IP_AFTER" ]]; then
  echo "VPN connection is still active on $VPN_INTERFACE with IP $VPN_IP."
else
  echo "VPN connection has been interrupted."
  exit 1
fi

echo "Setup complete. Your VPN connection over wlan0 should remain active even after connecting to the internal network via eth0."
