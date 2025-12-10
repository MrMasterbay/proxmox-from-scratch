#!/bin/bash

# Proxmox VE Installation Script for Debian 13 (Trixie)
# WARNING: This script significantly modifies your system!

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions for colored output
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root!"
   exit 1
fi

# Check Debian version
print_step "Checking Debian version..."
if ! grep -q "trixie\|13" /etc/debian_version 2>/dev/null && ! grep -q "trixie" /etc/os-release 2>/dev/null; then
    print_warn "Warning: This does not appear to be Debian 13 (Trixie)!"
    read -p "Continue anyway? (yes/no): " confirm
    if [[ $confirm != "yes" ]]; then
        exit 1
    fi
fi

# Check hostname
print_step "Checking hostname configuration..."
HOSTNAME=$(hostname)
FQDN=$(hostname -f 2>/dev/null || echo "")

if [[ -z "$FQDN" ]] || [[ "$FQDN" == "$HOSTNAME" ]]; then
    print_warn "No complete FQDN (Fully Qualified Domain Name) found!"
    echo "Proxmox requires a valid FQDN."
    read -p "Enter FQDN (e.g. pve.example.com): " NEW_FQDN
    
    if [[ -n "$NEW_FQDN" ]]; then
        HOSTNAME_SHORT=$(echo $NEW_FQDN | cut -d. -f1)
        hostnamectl set-hostname $HOSTNAME_SHORT
        
        # Adjust /etc/hosts
        IP_ADDRESS=$(hostname -I | awk '{print $1}')
        if [[ -z "$IP_ADDRESS" ]]; then
            print_error "No IP address found!"
            exit 1
        fi
        
        # Backup hosts file
        cp /etc/hosts /etc/hosts.backup
        
        # Create new hosts file
        cat > /etc/hosts <<EOF
127.0.0.1       localhost
$IP_ADDRESS     $NEW_FQDN $HOSTNAME_SHORT

# IPv6
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF
        print_info "Hostname set to $NEW_FQDN"
    fi
fi

# Detect network interface
print_step "Detecting network configuration..."

# Find active interface
PRIMARY_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

if [[ -z "$PRIMARY_INTERFACE" ]]; then
    print_error "No active network interface found!"
    echo ""
    echo "Available interfaces:"
    ip link show | grep -E "^[0-9]+" | awk '{print "  - " $2}' | sed 's/:$//'
    echo ""
    read -p "Please enter interface name (e.g. eth0, ens18, enp0s3): " PRIMARY_INTERFACE
    
    # Validate interface exists
    if ! ip link show "$PRIMARY_INTERFACE" &>/dev/null; then
        print_error "Interface $PRIMARY_INTERFACE does not exist!"
        exit 1
    fi
fi

# Check if interface is already a bridge
if [[ -d "/sys/class/net/$PRIMARY_INTERFACE/bridge" ]]; then
    print_error "Interface $PRIMARY_INTERFACE is already a bridge!"
    print_error "Cannot enslave a bridge to another bridge."
    exit 1
fi

print_info "Primary interface: $PRIMARY_INTERFACE"

# Check interface state
INTERFACE_STATE=$(ip link show $PRIMARY_INTERFACE | grep -oP '(?<=state )\w+')
print_info "Interface state: $INTERFACE_STATE"

if [[ "$INTERFACE_STATE" != "UP" ]]; then
    print_warn "Warning: Interface is not UP!"
    read -p "Continue anyway? (yes/no): " continue_down
    if [[ $continue_down != "yes" ]]; then
        exit 1
    fi
fi

# Read current IP configuration
CURRENT_IP=$(ip -4 addr show $PRIMARY_INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
CURRENT_NETMASK=$(ip -4 addr show $PRIMARY_INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | head -n1 | cut -d'/' -f2)
CURRENT_GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)

# Detect DNS server
CURRENT_DNS=$(grep -m1 "^nameserver" /etc/resolv.conf | awk '{print $2}')
if [[ -z "$CURRENT_DNS" ]]; then
    CURRENT_DNS="8.8.8.8"
    print_warn "No DNS server found in /etc/resolv.conf, using default: $CURRENT_DNS"
fi

print_info "Current configuration:"
echo "  Interface:   $PRIMARY_INTERFACE"
echo "  IP Address:  $CURRENT_IP/$CURRENT_NETMASK"
echo "  Gateway:     $CURRENT_GATEWAY"
echo "  DNS:         $CURRENT_DNS"
echo ""

if [[ -z "$CURRENT_IP" ]] || [[ -z "$CURRENT_GATEWAY" ]]; then
    print_warn "Warning: IP or Gateway not detected automatically!"
    print_warn "Manual configuration required."
    echo ""
fi

read -p "Use this configuration for vmbr0? (yes/no): " use_current

if [[ $use_current != "yes" ]]; then
    read -p "IP Address (e.g. 192.168.1.100): " CURRENT_IP
    read -p "Netmask (CIDR, e.g. 24): " CURRENT_NETMASK
    read -p "Gateway: " CURRENT_GATEWAY
    read -p "DNS Server (comma-separated, e.g. 8.8.8.8,8.8.4.4): " CURRENT_DNS
fi

# Validate IP configuration
if [[ -z "$CURRENT_IP" ]] || [[ -z "$CURRENT_NETMASK" ]] || [[ -z "$CURRENT_GATEWAY" ]]; then
    print_error "Incomplete network configuration!"
    exit 1
fi

# Update system
print_step "Updating system..."
apt-get update
apt-get dist-upgrade -y

# Install prerequisites
print_step "Installing prerequisites..."
apt-get install -y \
    gnupg \
    ca-certificates \
    curl \
    wget \
    software-properties-common \
    ifupdown2 \
    bridge-utils

# Add Proxmox VE repository
print_step "Adding Proxmox VE repository..."

# Add Proxmox GPG key
curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg \
    -o /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg

# Add Proxmox repository
cat > /etc/apt/sources.list.d/pve-install-repo.list <<EOF
# Proxmox VE Repository (No-Subscription)
deb http://download.proxmox.com/debian/pve trixie pve-no-subscription
EOF

print_warn "NOTE: Using the No-Subscription repository."
print_warn "For production environments, a subscription is recommended!"

# Optional: Enterprise repository (commented out)
cat > /etc/apt/sources.list.d/pve-enterprise.list <<EOF
# Proxmox VE Enterprise Repository (requires subscription)
# deb https://enterprise.proxmox.com/debian/pve trixie pve-enterprise
EOF

# Update system again
print_step "Updating package lists..."
apt-get update

# Install Proxmox VE
print_step "Installing Proxmox VE (this may take several minutes)..."
DEBIAN_FRONTEND=noninteractive apt-get install -y proxmox-ve postfix open-iscsi chrony

# Configure Postfix
print_step "Configuring Postfix..."
if [[ ! -f /etc/postfix/main.cf.backup ]]; then
    cp /etc/postfix/main.cf /etc/postfix/main.cf.backup
fi

# Create network configuration for Proxmox (vmbr0)
print_step "Configuring network bridge (vmbr0)..."
print_info "Interface $PRIMARY_INTERFACE will be enslaved to vmbr0"
print_info "This means $PRIMARY_INTERFACE becomes a slave port of the bridge"

# Backup current network configuration
if [[ -f /etc/network/interfaces ]]; then
    BACKUP_FILE="/etc/network/interfaces.backup.$(date +%Y%m%d_%H%M%S)"
    cp /etc/network/interfaces "$BACKUP_FILE"
    print_info "Backup created: $BACKUP_FILE"
fi

# Check for existing network config (Netplan, NetworkManager, etc.)
if [[ -d /etc/netplan ]] && ls /etc/netplan/*.yaml &>/dev/null; then
    print_warn "Netplan configuration detected!"
    print_warn "Netplan will be disabled in favor of ifupdown2"
    mkdir -p /etc/netplan.backup
    mv /etc/netplan/*.yaml /etc/netplan.backup/ 2>/dev/null || true
fi

# Disable NetworkManager if present
if systemctl is-active --quiet NetworkManager; then
    print_info "Disabling NetworkManager..."
    systemctl stop NetworkManager
    systemctl disable NetworkManager
    systemctl mask NetworkManager
fi

# Disable systemd-networkd if present
if systemctl is-active --quiet systemd-networkd; then
    print_info "Disabling systemd-networkd..."
    systemctl stop systemd-networkd
    systemctl disable systemd-networkd
fi

# Create new /etc/network/interfaces with explicit bridge configuration
cat > /etc/network/interfaces <<EOF
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

# Loopback Interface
auto lo
iface lo inet loopback

# Physical Interface - Enslaved to vmbr0 Bridge
# This interface is now a slave/port of the bridge and has no IP itself
auto $PRIMARY_INTERFACE
iface $PRIMARY_INTERFACE inet manual
    # Interface is enslaved to bridge vmbr0
    # No IP configuration on physical interface

# Proxmox Virtual Bridge vmbr0
# The bridge gets the IP configuration and enslaves $PRIMARY_INTERFACE
auto vmbr0
iface vmbr0 inet static
    # IP configuration moved from $PRIMARY_INTERFACE to bridge
    address $CURRENT_IP/$CURRENT_NETMASK
    gateway $CURRENT_GATEWAY
    # Bridge settings
    bridge-ports $PRIMARY_INTERFACE
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 2-4094
    # DNS Configuration
    dns-nameservers $CURRENT_DNS

# Additional bridges can be added here for VM networks
# Example:
# auto vmbr1
# iface vmbr1 inet static
#     address 10.0.0.1/24
#     bridge-ports none
#     bridge-stp off
#     bridge-fd 0
EOF

print_info "Network configuration created:"
echo ""
cat /etc/network/interfaces
echo ""

print_info "Configuration summary:"
echo "  ├─ Physical Interface: $PRIMARY_INTERFACE"
echo "  │  └─ Mode: manual (no IP, enslaved to bridge)"
echo "  └─ Bridge: vmbr0"
echo "     ├─ Slave port: $PRIMARY_INTERFACE"
echo "     ├─ IP: $CURRENT_IP/$CURRENT_NETMASK"
echo "     ├─ Gateway: $CURRENT_GATEWAY"
echo "     └─ DNS: $CURRENT_DNS"
echo ""

# Optional: Remove Debian kernel (recommended for Proxmox)
echo ""
read -p "Remove Debian kernel and keep only Proxmox kernel? (yes/no): " remove_kernel
if [[ $remove_kernel == "yes" ]]; then
    print_step "Removing Debian kernel..."
    apt-get remove -y linux-image-amd64 'linux-image-6.1*' || true
    update-grub
fi

# Disable Enterprise repository (if no subscription present)
print_step "Disabling Enterprise repository..."
if [[ -f /etc/apt/sources.list.d/pve-enterprise.list ]]; then
    sed -i 's/^deb/#deb/g' /etc/apt/sources.list.d/pve-enterprise.list
fi

# Check LVM thin provisioning
if ! command -v thin_check &> /dev/null; then
    print_warn "thin_check not found, installing thin-provisioning-tools..."
    apt-get install -y thin-provisioning-tools
fi

# Display storage configuration
print_step "Checking storage configuration..."
if command -v pvesm &> /dev/null; then
    echo "Available storage:"
    pvesm status 2>/dev/null || echo "  (Available after reboot)"
fi

# Firewall status
print_info "Proxmox Firewall is disabled by default"
print_info "Can be configured later via the web interface"

# Create summary
print_step "================================"
print_info "Installation completed!"
print_step "================================"
echo ""
print_info "Proxmox VE Web Interface:"
echo -e "  ${GREEN}https://${CURRENT_IP}:8006${NC}"
echo ""
print_info "Login:"
echo "  Username: root"
echo "  Password: Your root password"
echo ""
print_info "Network Configuration:"
echo "  Bridge:           vmbr0"
echo "  Bridge Slave:     $PRIMARY_INTERFACE (enslaved)"
echo "  IP Address:       $CURRENT_IP/$CURRENT_NETMASK"
echo "  Gateway:          $CURRENT_GATEWAY"
echo "  DNS:              $CURRENT_DNS"
echo ""
print_warn "IMPORTANT: System needs to be rebooted!"
print_warn "After reboot, the vmbr0 bridge will be active."
print_warn "Physical interface $PRIMARY_INTERFACE will be a slave port."
echo ""

# Create network test script
cat > /root/proxmox-network-test.sh <<'EOF'
#!/bin/bash
echo "=== Proxmox Network Status ==="
echo ""
echo "1. Bridge Status:"
ip addr show vmbr0
echo ""
echo "2. Bridge Ports/Slaves:"
brctl show vmbr0
echo ""
echo "3. Physical Interface Status:"
IFACE=$(brctl show vmbr0 | tail -n1 | awk '{print $NF}')
if [[ -n "$IFACE" ]]; then
    ip link show $IFACE
    echo "Interface $IFACE is enslaved to vmbr0: $(cat /sys/class/net/$IFACE/master 2>/dev/null | grep -o 'vmbr0' || echo 'NO')"
fi
echo ""
echo "4. Routing Table:"
ip route
echo ""
echo "5. Gateway Ping Test:"
GATEWAY=$(ip route | grep default | awk '{print $3}')
if [[ -n "$GATEWAY" ]]; then
    ping -c 3 $GATEWAY
else
    echo "No default gateway found!"
fi
echo ""
echo "6. DNS Test:"
ping -c 3 8.8.8.8
echo ""
echo "7. Bridge Details:"
ip -d link show vmbr0
EOF

chmod +x /root/proxmox-network-test.sh
print_info "Network test script created: /root/proxmox-network-test.sh"

# Create recovery script
cat > /root/proxmox-network-recovery.sh <<EOF
#!/bin/bash
# Proxmox Network Recovery Script
echo "=== Network Recovery ==="
echo ""
echo "Available backups:"
ls -la /etc/network/interfaces.backup.* 2>/dev/null || echo "No backups found"
echo ""
read -p "Enter backup file to restore (full path): " BACKUP
if [[ -f "\$BACKUP" ]]; then
    cp "\$BACKUP" /etc/network/interfaces
    echo "Backup restored. Restarting network..."
    systemctl restart networking
    echo "Network restarted. Checking status..."
    ip addr show
else
    echo "File not found!"
fi
EOF

chmod +x /root/proxmox-network-recovery.sh
print_info "Recovery script created: /root/proxmox-network-recovery.sh"

echo ""
print_step "Post-Reboot Verification Steps:"
echo "1. Run network test: /root/proxmox-network-test.sh"
echo "2. Check bridge: brctl show vmbr0"
echo "3. Verify slave: cat /sys/class/net/$PRIMARY_INTERFACE/master"
echo "4. Access web interface: https://${CURRENT_IP}:8006"
echo ""

read -p "Reboot now? (yes/no): " reboot_now
if [[ $reboot_now == "yes" ]]; then
    print_info "System will reboot now..."
    print_warn "If network problems occur:"
    echo "  1. Connect via iLO/IPMI/Console"
    echo "  2. Run recovery script: /root/proxmox-network-recovery.sh"
    echo "  3. Or manually restore: cp $BACKUP_FILE /etc/network/interfaces"
    echo "  4. Restart network: systemctl restart networking"
    sleep 5
    reboot
else
    print_warn "Please reboot the system manually: reboot"
    echo ""
    print_info "After reboot, verify network with:"
    echo "  /root/proxmox-network-test.sh"
fi
