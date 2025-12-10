# Debian 13 to Proxmox VE Converter

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Debian](https://img.shields.io/badge/Debian-13%20(Trixie)-red.svg)
![Proxmox](https://img.shields.io/badge/Proxmox-VE%209.x-orange.svg)

Automated script to convert a fresh Debian 13 (Trixie) installation into a fully functional Proxmox VE hypervisor with proper network bridge configuration.

## ⚠️ Warning

This script makes **significant changes** to your system:
- Modifies network configuration
- Changes kernel
- Installs hypervisor components
- Reconfigures network interfaces

**ALWAYS create a backup before running this script!**

## ✨ Features

- ✅ Automatic Debian 13 detection
- ✅ FQDN configuration
- ✅ Proxmox VE repository setup (no-subscription)
- ✅ Automatic network interface detection
- ✅ Bridge (vmbr0) creation with interface enslavement
- ✅ IP configuration migration
- ✅ NetworkManager/systemd-networkd handling
- ✅ Postfix configuration
- ✅ Optional Debian kernel removal
- ✅ Post-installation network testing tools
- ✅ Automatic backup of configurations
- ✅ Recovery scripts included

## 📋 Prerequisites

- Fresh Debian 13 (Trixie) installation
- Root access
- Active internet connection
- Static IP address (recommended)
- Valid FQDN or ability to set one

### Minimum System Requirements

- **CPU**: 64-bit processor with virtualization support (Intel VT-x/AMD-V)
- **RAM**: 2 GB minimum (4 GB+ recommended)
- **Disk**: 20 GB minimum
- **Network**: Static IP recommended

## 🚀 Quick Start

### 1. Download the Script

```bash
wget https://raw.githubusercontent.com/MrMasterbay/proxmox-from-scratch/main/little-goblin.sh
# or
curl -O https://raw.githubusercontent.com/MrMasterbay/proxmox-from-scratch/main/little-goblin.sh
```

### 2. Make it Executable

```bash
chmod +x little-goblin.sh
```

### 3. Run as Root

```bash
sudo ./little-goblin.sh
```

### 4. Follow the Prompts

The script will guide you through:
- FQDN configuration
- Network interface detection
- IP configuration confirmation
- Kernel removal option
- Reboot confirmation

### 5. Access Proxmox Web Interface

After reboot, access the web interface at:
```
https://YOUR-IP-ADDRESS:8006
```

**Default credentials:**
- Username: `root`
- Password: Your root password

## 📖 Detailed Usage

### Pre-Installation Checklist

```bash
# Check Debian version
cat /etc/debian_version
# Should show: trixie/sid or 13.x

# Check network configuration
ip addr show
ip route

# Verify internet connectivity
ping -c 3 google.com

# Check hostname
hostname -f
```

### Network Configuration

The script will:

1. **Detect** your primary network interface (e.g., `eth0`, `ens18`)
2. **Read** current IP configuration
3. **Create** bridge `vmbr0`
4. **Enslave** physical interface to bridge
5. **Transfer** IP configuration to bridge

**Before:**
```
eth0: 192.168.1.100/24
```

**After:**
```
eth0: no IP (enslaved to vmbr0)
vmbr0: 192.168.1.100/24 (bridge with eth0 as slave)
```

### Example Session

```bash
root@debian:~# ./little-goblin.sh

[STEP] Checking Debian version...
[INFO] Debian 13 (Trixie) detected

[STEP] Checking hostname configuration...
[WARN] No complete FQDN found!
Enter FQDN (e.g. pve.example.com): pve.homelab.local
[INFO] Hostname set to pve.homelab.local

[STEP] Detecting network configuration...
[INFO] Primary interface: ens18
[INFO] Current configuration:
  Interface:   ens18
  IP Address:  192.168.1.100/24
  Gateway:     192.168.1.1
  DNS:         192.168.1.1

Use this configuration for vmbr0? (yes/no): yes

[STEP] Updating system...
[STEP] Installing prerequisites...
[STEP] Adding Proxmox VE repository...
[STEP] Installing Proxmox VE (this may take several minutes)...
[STEP] Configuring network bridge (vmbr0)...
[INFO] Interface ens18 will be enslaved to vmbr0

Remove Debian kernel and keep only Proxmox kernel? (yes/no): yes

[INFO] Installation completed!
[INFO] Proxmox VE Web Interface: https://192.168.1.100:8006

Reboot now? (yes/no): yes
```

## 🔧 Post-Installation

### Network Verification

After reboot, run the included test script:

```bash
/root/proxmox-network-test.sh
```

This will check:
- Bridge status
- Enslaved interfaces
- Routing
- Gateway connectivity
- DNS resolution

### Manual Verification

```bash
# Check bridge configuration
brctl show vmbr0

# Verify interface enslavement
cat /sys/class/net/ens18/master
# Should output: vmbr0

# Check IP addresses
ip addr show vmbr0  # Should have your IP
ip addr show ens18  # Should NOT have an IP

# Test connectivity
ping -c 3 8.8.8.8
```

### Verify Proxmox Services

```bash
# Check Proxmox services
systemctl status pve-cluster
systemctl status pvedaemon
systemctl status pveproxy

# Check Proxmox version
pveversion
```

## 🆘 Troubleshooting

### Network Not Working After Reboot

**Option 1: Use Recovery Script**
```bash
/root/proxmox-network-recovery.sh
```

**Option 2: Manual Recovery via Console/IPMI**
```bash
# List available backups
ls -la /etc/network/interfaces.backup.*

# Restore backup
cp /etc/network/interfaces.backup.YYYYMMDD_HHMMSS /etc/network/interfaces

# Restart network
systemctl restart networking

# Or reboot
reboot
```

**Option 3: Manual Bridge Configuration**
```bash
# Bring down bridge
ip link set vmbr0 down

# Reconfigure interface
ip addr add 192.168.1.100/24 dev ens18
ip link set ens18 up
ip route add default via 192.168.1.1
```

### Cannot Access Web Interface

```bash
# Check if services are running
systemctl status pveproxy
systemctl status pvedaemon

# Check firewall (if enabled)
iptables -L -n

# Check if port 8006 is listening
netstat -tlnp | grep 8006

# Restart Proxmox services
systemctl restart pveproxy
```

### Bridge Not Showing Slave Interface

```bash
# Check bridge ports
ls /sys/class/net/vmbr0/brif/

# Manually add interface to bridge
ip link set ens18 master vmbr0

# Or reconfigure via interfaces file
ifreload -a
```

### DNS Not Working

```bash
# Check resolv.conf
cat /etc/resolv.conf

# Add DNS manually to /etc/network/interfaces
# Under vmbr0 section:
dns-nameservers 8.8.8.8 8.8.4.4

# Restart networking
systemctl restart networking
```

### Common Error Messages

| Error | Solution |
|-------|----------|
| `Interface already a bridge` | Choose a different physical interface |
| `No IP address found` | Configure static IP before running script |
| `FQDN resolution fails` | Check `/etc/hosts` and DNS configuration |
| `Repository not found` | Check internet connection and try again |
| `Package conflicts` | Run `apt-get dist-upgrade` first |

## 📁 Generated Files

The script creates several files:

| File | Purpose |
|------|---------|
| `/etc/network/interfaces` | New network configuration |
| `/etc/network/interfaces.backup.*` | Backup of original config |
| `/etc/hosts.backup` | Backup of hosts file |
| `/root/proxmox-network-test.sh` | Network testing script |
| `/root/proxmox-network-recovery.sh` | Quick recovery script |
| `/etc/apt/sources.list.d/pve-install-repo.list` | Proxmox repository |

## 🔐 Security Considerations

### After Installation

1. **Change root password**
   ```bash
   passwd
   ```

2. **Configure Proxmox firewall** (via web interface)
   - Datacenter → Firewall → Enable

3. **Set up 2FA** (optional)
   - Datacenter → Permissions → Two Factor

4. **Create non-root users**
   - Datacenter → Permissions → Users

5. **Consider subscription** for production use
   - Removes repository nag
   - Provides enterprise support
   - Access to tested repositories

### Repository Note

This script uses the **no-subscription** repository:
```
deb http://download.proxmox.com/debian/pve trixie pve-no-subscription
```

For production environments, consider purchasing a subscription:
```
deb https://enterprise.proxmox.com/debian/pve trixie pve-enterprise
```

## 📝 Changelog

### v1.0.0 (10.12.2025)
- Initial release
- Automatic network detection
- Bridge configuration with interface enslavement
- Recovery scripts
- Post-installation testing tools

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Proxmox VE Team for excellent virtualization platform
- Debian Project for stable base system
- Community contributors and testers

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/MrMasterbay/proxmox-from-scratch/issues)
- **Discussions**: [GitHub Discussions](https://github.com/MrMasterbay/proxmox-from-scratch/discussions)
- **Proxmox Forum**: [forum.proxmox.com](https://forum.proxmox.com)
- **Proxmox Wiki**: [pve.proxmox.com/wiki](https://pve.proxmox.com/wiki)

## ⚖️ Disclaimer

This script is provided "as is" without warranty of any kind. Always backup your system before making significant changes. The authors are not responsible for any data loss or system issues resulting from the use of this script.

## 🔗 Useful Links

- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [Proxmox VE Administration Guide](https://pve.proxmox.com/pve-docs/pve-admin-guide.html)
- [Debian Network Configuration](https://wiki.debian.org/NetworkConfiguration)
- [Linux Bridge Configuration](https://wiki.debian.org/BridgeNetworkConnections)

---

**Made with ❤️ for the homelab community**

*Star ⭐ this repository if you find it useful!*
