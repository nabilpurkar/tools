# Cross-Platform Proxy Configuration Guide
A comprehensive guide for setting up and removing proxy configuration for nodes without direct internet access.

## RHEL/CentOS Setup Instructions

### 1. On Proxy Node with Internet
```bash
# Install and configure Squid
sudo dnf install squid -y

# Create new squid config
sudo bash -c 'cat > /etc/squid/squid.conf << EOF
http_port 3128

acl SSL_ports port 443
acl Safe_ports port 80          # http
acl Safe_ports port 443         # https
acl Safe_ports port 81          # custom repos
acl CONNECT method CONNECT

http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow localhost manager
http_access deny manager

acl localnet src 172.31.0.0/16
http_access allow localnet
http_access allow localhost
http_access deny all

coredump_dir /var/spool/squid
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern ^gopher:        1440    0%      1440
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320
EOF'

# Start and enable Squid
sudo systemctl enable squid
sudo systemctl restart squid

# Allow Squid port in firewall
sudo firewall-cmd --add-port=3128/tcp --permanent
sudo firewall-cmd --reload
```

## Ubuntu/Debian Setup Instructions

### 1. On Proxy Node with Internet
```bash
# Install and configure Squid
sudo apt update
sudo apt install squid -y

# Create new squid config (same configuration as RHEL)
sudo bash -c 'cat > /etc/squid/squid.conf << EOF
# Same configuration as above
EOF'

# Start and enable Squid
sudo systemctl enable squid
sudo systemctl restart squid

# Configure UFW firewall
sudo ufw allow 3128/tcp
sudo ufw reload
```

## Windows Setup Instructions

### 1. On Proxy Node with Internet
```powershell
# Install Squid using Chocolatey
choco install squid

# Configure Squid (Path: C:\Squid\etc\squid.conf)
# Use same configuration as above, adjusting paths

# Start Squid service
net start squidsrv

# Configure Windows Firewall
netsh advfirewall firewall add rule name="Squid Proxy" dir=in action=allow protocol=TCP localport=3128
```

## Client Configuration (All OS)

### RHEL/CentOS Client
```bash
# Configure DNF proxy
sudo bash -c 'cat > /etc/dnf/dnf.conf << EOF
[main]
gpgcheck=1
installonly_limit=3
clean_requirements_on_remove=True
best=True
proxy=http://SQUID_NODE_IP:3128
EOF'

# Set environment variables
export http_proxy=http://SQUID_NODE_IP:3128
export https_proxy=http://SQUID_NODE_IP:3128
```

### Ubuntu/Debian Client
```bash
# Configure APT proxy
sudo bash -c 'cat > /etc/apt/apt.conf.d/proxy.conf << EOF
Acquire::http::Proxy "http://SQUID_NODE_IP:3128";
Acquire::https::Proxy "http://SQUID_NODE_IP:3128";
EOF'

# Set environment variables (same as RHEL)
```

### Windows Client
```powershell
# Set system-wide proxy
netsh winhttp set proxy proxy-server="http=SQUID_NODE_IP:3128;https=SQUID_NODE_IP:3128"

# Set environment variables
[Environment]::SetEnvironmentVariable("http_proxy", "http://SQUID_NODE_IP:3128", "Machine")
[Environment]::SetEnvironmentVariable("https_proxy", "http://SQUID_NODE_IP:3128", "Machine")
```

## Removal Instructions

### RHEL/CentOS
```bash
# Remove proxy configurations
sudo rm -f /etc/yum.repos.d/proxy.conf
sudo sed -i '/proxy/d' /etc/yum.conf
sudo rm -f /etc/dnf/dnf.conf.d/*proxy*
sudo rm -f /etc/profile.d/proxy.sh

# Reset DNF configuration
sudo bash -c 'cat > /etc/dnf/dnf.conf << EOF
[main]
gpgcheck=1
installonly_limit=3
clean_requirements_on_remove=True
best=True
EOF'

# Unset environment variables
unset http_proxy
unset https_proxy

# Clean DNF cache
sudo dnf clean all
```

### Ubuntu/Debian
```bash
# Remove proxy configurations
sudo rm -f /etc/apt/apt.conf.d/proxy.conf
sudo apt remove squid -y
sudo ufw delete allow 3128/tcp
```

### Windows
```powershell
# Remove system proxy
netsh winhttp reset proxy

# Remove environment variables
[Environment]::SetEnvironmentVariable("http_proxy", $null, "Machine")
[Environment]::SetEnvironmentVariable("https_proxy", $null, "Machine")

# Stop and remove Squid service
net stop squidsrv
choco uninstall squid -y
```

## Important Notes
- Replace `SQUID_NODE_IP` with your actual proxy server IP address
- Verify connectivity between nodes before setup
- Backup important configurations before making changes
- Some applications may require additional proxy configuration
- For Windows, ensure PowerShell is run as Administrator
- Consider security implications when opening firewall ports

## Verification Steps

### Testing Proxy Connection (All OS)
```bash
# Linux
curl -v http://SQUID_NODE_IP:3128

# Windows PowerShell
Invoke-WebRequest -Uri http://SQUID_NODE_IP:3128 -Verbose
```

### Package Manager Test
```bash
# RHEL/CentOS
sudo dnf update --verbose

# Ubuntu/Debian
sudo apt update

# Windows (Chocolatey)
choco list --verbose
```
