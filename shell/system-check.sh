#!/bin/bash

# Colorize terminal
red='\e[0;31m'
green='\e[0;32m'
yellow='\e[0;33m'
blue='\e[0;34m'
cyan='\e[0;36m'
no_color='\033[0m'

# Console step increment
i=1

# Default settings
VERBOSE="false"
OUTPUT_FILE=""

# Declare script helper
TEXT_HELPER="\nThis script performs a quick system diagnostic on Linux systems.
Following flags are available:

  -v    (Optional) Verbose mode - show more details.
        Default is '$VERBOSE'.

  -o    (Optional) Save output to file.
        Example: -o /tmp/system-check.txt

  -h    Print script help.\n\n"

print_help() {
  printf "$TEXT_HELPER"
}

# Parse options
while getopts hvo: flag; do
  case "${flag}" in
    v)
      VERBOSE="true";;
    o)
      OUTPUT_FILE="${OPTARG}";;
    h | *)
      print_help
      exit 0;;
  esac
done

# Function to print section header
print_section() {
  printf "\n${red}${i}.${no_color} ${blue}$1${no_color}\n"
  i=$(($i + 1))
}

# Function to print key-value pair
print_info() {
  printf "  ${cyan}→${no_color} %-20s ${green}%s${no_color}\n" "$1:" "$2"
}

# Function to print warning
print_warning() {
  printf "  ${yellow}⚠${no_color} %s\n" "$1"
}

# Function to check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Redirect output if needed
if [ -n "$OUTPUT_FILE" ]; then
  exec > >(tee "$OUTPUT_FILE")
fi

# Start diagnostic
printf "\n${blue}╔════════════════════════════════════════╗${no_color}\n"
printf "${blue}║${no_color}     ${green}Linux System Diagnostic${no_color}       ${blue}║${no_color}\n"
printf "${blue}╚════════════════════════════════════════╝${no_color}\n"
printf "Generated: $(date +'%Y-%m-%d %H:%M:%S')\n"


# 1. OS Information
print_section "Operating System"

if [ -f /etc/os-release ]; then
  . /etc/os-release
  print_info "Distribution" "$NAME"
  [ -n "$VERSION" ] && print_info "Version" "$VERSION"
  [ -n "$VERSION_CODENAME" ] && print_info "Codename" "$VERSION_CODENAME"
elif [ -f /etc/redhat-release ]; then
  print_info "Distribution" "$(cat /etc/redhat-release)"
else
  print_info "Distribution" "Unknown"
fi

print_info "Kernel" "$(uname -r)"
print_info "Architecture" "$(uname -m)"
HOSTNAME=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || hostnamectl hostname 2>/dev/null || echo "unknown")
print_info "Hostname" "$HOSTNAME"

# Detect Desktop Environment
if [ -n "$XDG_CURRENT_DESKTOP" ]; then
  print_info "Desktop Environment" "$XDG_CURRENT_DESKTOP"
elif [ -n "$DESKTOP_SESSION" ]; then
  print_info "Desktop Environment" "$DESKTOP_SESSION"
elif [ -n "$GDMSESSION" ]; then
  print_info "Desktop Environment" "$GDMSESSION"
elif pgrep -x "Xorg" >/dev/null || pgrep -x "X" >/dev/null; then
  print_info "Display Server" "X11 (no DE detected)"
elif pgrep -x "wayland" >/dev/null || [ -n "$WAYLAND_DISPLAY" ]; then
  print_info "Display Server" "Wayland (no DE detected)"
else
  print_info "Environment" "Headless/Server"
fi

# Detect if running in container
if [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
  print_info "Container" "Docker"
elif grep -q lxc /proc/1/cgroup 2>/dev/null; then
  print_info "Container" "LXC"
elif [ -f /run/systemd/container ]; then
  print_info "Container" "$(cat /run/systemd/container)"
fi


# 2. System Uptime & Load
print_section "System Status"

print_info "Uptime" "$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')"
print_info "Load Average" "$(uptime | awk -F'load average:' '{print $2}')"

if [ -f /proc/sys/kernel/hostname ]; then
  print_info "Boot Time" "$(who -b 2>/dev/null | awk '{print $3, $4}' || echo 'N/A')"
fi


# 3. Hardware Information
print_section "Hardware"

# CPU
CPU_MODEL=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d':' -f2 | xargs)
CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)
print_info "CPU" "$CPU_MODEL"
print_info "Cores/Threads" "$CPU_CORES"

# Memory
if command_exists free; then
  MEM_TOTAL=$(free -h | awk '/^Mem:/ {print $2}')
  MEM_USED=$(free -h | awk '/^Mem:/ {print $3}')
  MEM_AVAILABLE=$(free -h | awk '/^Mem:/ {print $7}')
  MEM_PERCENT=$(free | awk '/^Mem:/ {printf("%.1f%%", $3/$2 * 100)}')
  print_info "Memory Total" "$MEM_TOTAL"
  print_info "Memory Used" "$MEM_USED ($MEM_PERCENT)"
  print_info "Memory Available" "$MEM_AVAILABLE"
fi


# 4. Disk Usage
print_section "Disk Usage"

if command_exists df; then
  while IFS= read -r line; do
    FILESYSTEM=$(echo "$line" | awk '{print $1}')
    SIZE=$(echo "$line" | awk '{print $2}')
    USED=$(echo "$line" | awk '{print $3}')
    AVAIL=$(echo "$line" | awk '{print $4}')
    PERCENT=$(echo "$line" | awk '{print $5}')
    MOUNT=$(echo "$line" | awk '{print $6}')
    
    printf "  ${cyan}→${no_color} %-20s %s (Used: %s/%s - %s)\n" "$MOUNT" "$AVAIL free" "$USED" "$SIZE" "$PERCENT"
    
    # Warning if > 85%
    PERCENT_NUM=$(echo "$PERCENT" | sed 's/%//')
    if [ "$PERCENT_NUM" -gt 85 ] 2>/dev/null; then
      print_warning "High disk usage on $MOUNT"
    fi
  done < <(df -h | grep -vE '^tmpfs|^devtmpfs|^udev|^Filesystem' | grep -E '^/')
fi


# 5. Network Configuration
print_section "Network"

if command_exists ip; then
  # Get primary IP (Alpine/BusyBox compatible)
  PRIMARY_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
  PRIMARY_IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
  [ -z "$PRIMARY_IP" ] && PRIMARY_IP="N/A"
  [ -z "$PRIMARY_IFACE" ] && PRIMARY_IFACE="N/A"
  print_info "Primary Interface" "$PRIMARY_IFACE"
  print_info "Primary IP" "$PRIMARY_IP"
  
  if [ "$VERBOSE" = "true" ]; then
    printf "\n  ${cyan}All interfaces:${no_color}\n"
    ip -br addr show | while read -r line; do
      printf "    %s\n" "$line"
    done
  fi
elif command_exists ifconfig; then
  print_info "Network" "$(ifconfig | grep 'inet ' | head -1 | awk '{print $2}')"
fi

# DNS
if [ -f /etc/resolv.conf ]; then
  DNS_SERVERS=$(grep -E '^nameserver' /etc/resolv.conf | awk '{print $2}' | tr '\n' ', ' | sed 's/,$//')
  print_info "DNS Servers" "${DNS_SERVERS:-N/A}"
fi


# 6. Services & Processes
print_section "Services & Processes"

print_info "Running Processes" "$(ps aux | wc -l)"
print_info "Logged Users" "$(who | wc -l)"

# Check if systemd is available
if command_exists systemctl; then
  FAILED_SERVICES=$(systemctl --failed --no-pager --no-legend | wc -l)
  print_info "Failed Services" "$FAILED_SERVICES"
  
  if [ "$FAILED_SERVICES" -gt 0 ] && [ "$VERBOSE" = "true" ]; then
    printf "\n  ${yellow}Failed services:${no_color}\n"
    systemctl --failed --no-pager --no-legend | while read -r line; do
      printf "    %s\n" "$line"
    done
  fi
fi

# Top CPU processes
if [ "$VERBOSE" = "true" ]; then
  printf "\n  ${cyan}Top 5 CPU processes:${no_color}\n"
  ps aux --sort=-%cpu | head -6 | tail -5 | awk '{printf "    %-10s %5s%%  %s\n", $1, $3, $11}'
  
  printf "\n  ${cyan}Top 5 Memory processes:${no_color}\n"
  ps aux --sort=-%mem | head -6 | tail -5 | awk '{printf "    %-10s %5s%%  %s\n", $1, $4, $11}'
fi


# 7. Security & Updates
print_section "Security"

# Check if running as root (compatible with sh)
CURRENT_USER=$(whoami 2>/dev/null || id -un 2>/dev/null)
if [ "$(id -u 2>/dev/null)" -eq 0 ] 2>/dev/null; then
  print_warning "Running as ROOT user"
else
  print_info "Current User" "$CURRENT_USER"
fi

# SSH status
if command_exists systemctl; then
  SSH_STATUS=$(systemctl is-active sshd 2>/dev/null || systemctl is-active ssh 2>/dev/null || echo "unknown")
  print_info "SSH Service" "$SSH_STATUS"
elif command_exists service; then
  service sshd status >/dev/null 2>&1 && print_info "SSH Service" "running" || print_info "SSH Service" "stopped/unknown"
fi

# Firewall status
if command_exists ufw; then
  UFW_STATUS=$(ufw status 2>/dev/null | grep -o "Status: .*" || echo "N/A")
  print_info "Firewall (ufw)" "$UFW_STATUS"
elif command_exists firewall-cmd; then
  FIREWALLD_STATUS=$(firewall-cmd --state 2>/dev/null || echo "N/A")
  print_info "Firewall (firewalld)" "$FIREWALLD_STATUS"
fi

# SELinux
if command_exists getenforce; then
  SELINUX_STATUS=$(getenforce 2>/dev/null || echo "N/A")
  print_info "SELinux" "$SELINUX_STATUS"
fi


# 8. System Logs & Errors
print_section "System Logs & Errors"

# Check for recent errors with journalctl (systemd)
if command_exists journalctl; then
  ERROR_COUNT=$(journalctl -p err -b --no-pager 2>/dev/null | wc -l)
  CRIT_COUNT=$(journalctl -p crit -b --no-pager 2>/dev/null | wc -l)
  
  print_info "Errors since boot" "$ERROR_COUNT"
  print_info "Critical since boot" "$CRIT_COUNT"
  
  if [ "$VERBOSE" = "true" ]; then
    # Show last 5 errors
    RECENT_ERRORS=$(journalctl -p err -b --no-pager -n 5 2>/dev/null | grep -v "^--" | tail -5)
    if [ -n "$RECENT_ERRORS" ]; then
      printf "\n  ${yellow}Last 5 errors:${no_color}\n"
      echo "$RECENT_ERRORS" | while IFS= read -r line; do
        printf "    %s\n" "$(echo "$line" | cut -c1-100)"
      done
    fi
  fi
  
  # Check for OOM kills
  OOM_KILLS=$(journalctl -b 2>/dev/null | grep -i "out of memory" | wc -l)
  if [ "$OOM_KILLS" -gt 0 ]; then
    print_warning "Out of Memory kills detected: $OOM_KILLS"
  fi
  
  # Check for kernel panics or oops
  KERNEL_ISSUES=$(journalctl -b 2>/dev/null | grep -iE "kernel panic|kernel oops|segfault" | wc -l)
  if [ "$KERNEL_ISSUES" -gt 0 ]; then
    print_warning "Kernel issues detected: $KERNEL_ISSUES"
  fi
  
elif [ -f /var/log/syslog ]; then
  # Fallback for systems without journalctl (older systems)
  ERROR_COUNT=$(grep -i "error" /var/log/syslog 2>/dev/null | wc -l || echo "0")
  print_info "Errors in syslog" "$ERROR_COUNT"
elif [ -f /var/log/messages ]; then
  ERROR_COUNT=$(grep -i "error" /var/log/messages 2>/dev/null | wc -l || echo "0")
  print_info "Errors in messages" "$ERROR_COUNT"
else
  print_info "Log Access" "Limited (no journalctl/syslog)"
fi

# Check dmesg for hardware errors
if command_exists dmesg; then
  DMESG_ERRORS=$(dmesg -l err,crit,alert,emerg 2>/dev/null | wc -l || echo "0")
  if [ "$DMESG_ERRORS" -gt 0 ]; then
    print_info "Hardware errors (dmesg)" "$DMESG_ERRORS"
    
    if [ "$VERBOSE" = "true" ]; then
      RECENT_DMESG=$(dmesg -l err,crit,alert,emerg 2>/dev/null | tail -3)
      if [ -n "$RECENT_DMESG" ]; then
        printf "  ${yellow}Recent hardware errors:${no_color}\n"
        echo "$RECENT_DMESG" | while IFS= read -r line; do
          printf "    %s\n" "$(echo "$line" | cut -c1-100)"
        done
      fi
    fi
  fi
fi

# Check for disk errors (SMART if available)
if command_exists smartctl && [ "$VERBOSE" = "true" ]; then
  SMART_AVAILABLE=$(smartctl --scan 2>/dev/null | wc -l)
  if [ "$SMART_AVAILABLE" -gt 0 ]; then
    print_info "SMART monitoring" "Available ($SMART_AVAILABLE disks)"
  fi
fi


# 9. Package Management
print_section "Package Management"

if command_exists apt; then
  print_info "Package Manager" "apt (Debian/Ubuntu)"
  if [ "$VERBOSE" = "true" ]; then
    UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -c upgradable || echo "0")
    print_info "Upgradable Packages" "$UPGRADABLE"
  fi
elif command_exists dnf; then
  print_info "Package Manager" "dnf (Fedora/RHEL 8+)"
  if [ "$VERBOSE" = "true" ]; then
    UPGRADABLE=$(dnf check-update 2>/dev/null | grep -E '^\S+' | wc -l || echo "0")
    print_info "Upgradable Packages" "$UPGRADABLE"
  fi
elif command_exists yum; then
  print_info "Package Manager" "yum (RHEL/CentOS)"
  if [ "$VERBOSE" = "true" ]; then
    UPGRADABLE=$(yum check-update 2>/dev/null | grep -E '^\S+' | wc -l || echo "0")
    print_info "Upgradable Packages" "$UPGRADABLE"
  fi
elif command_exists pacman; then
  print_info "Package Manager" "pacman (Arch)"
  if [ "$VERBOSE" = "true" ]; then
    UPGRADABLE=$(pacman -Qu 2>/dev/null | wc -l || echo "0")
    print_info "Upgradable Packages" "$UPGRADABLE"
  fi
elif command_exists zypper; then
  print_info "Package Manager" "zypper (openSUSE)"
elif command_exists apk; then
  print_info "Package Manager" "apk (Alpine)"
  if [ "$VERBOSE" = "true" ]; then
    UPGRADABLE=$(apk list --upgradable 2>/dev/null | grep -c 'upgradable' || echo "0")
    print_info "Upgradable Packages" "$UPGRADABLE"
  fi
fi


# 10. Essential Tools
print_section "Essential Tools"

check_tools() {
  category=$1
  shift
  installed=""
  missing=""
  
  for tool in "$@"; do
    if command_exists "$tool"; then
      installed="$installed $tool"
    else
      missing="$missing $tool"
    fi
  done
  
  if [ -n "$installed" ]; then
    printf "  ${cyan}→${no_color} %-20s ${green}%s${no_color}\n" "$category:" "$installed"
  fi
  
  if [ "$VERBOSE" = "true" ] && [ -n "$missing" ]; then
    printf "    ${yellow}Missing:${no_color} %s\n" "$missing"
  fi
}

check_tools "Core" bash sh tar gzip gunzip
check_tools "Network" curl wget nc netstat ss
check_tools "Transfer" rsync scp sftp
check_tools "Text Processing" awk sed grep find
if [ "$VERBOSE" = "true" ]; then
  check_tools "System" systemctl service ps top htop
  check_tools "Development" git make gcc python3 node npm
fi


# 11. Container Tools
if command_exists docker; then
  print_section "Docker"
  
  DOCKER_VERSION=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
  print_info "Version" "$DOCKER_VERSION"
  
  DOCKER_RUNNING=$(docker ps -q 2>/dev/null | wc -l || echo "N/A")
  DOCKER_TOTAL=$(docker ps -aq 2>/dev/null | wc -l || echo "N/A")
  print_info "Containers" "$DOCKER_RUNNING running / $DOCKER_TOTAL total"
  
  DOCKER_IMAGES=$(docker images -q 2>/dev/null | wc -l || echo "N/A")
  print_info "Images" "$DOCKER_IMAGES"
fi

if command_exists podman; then
  if ! command_exists docker; then
    print_section "Podman"
  fi
  PODMAN_VERSION=$(podman --version 2>/dev/null | awk '{print $3}')
  print_info "Podman Version" "$PODMAN_VERSION"
fi


# 12. Kubernetes (if installed)
if command_exists kubectl; then
  print_section "Kubernetes"
  
  KUBECTL_VERSION=$(kubectl version --client 2>/dev/null | awk '/Client Version:/ {print $3}' | head -1)
  [ -z "$KUBECTL_VERSION" ] && KUBECTL_VERSION=$(kubectl version --client --short 2>/dev/null | grep -o 'v[0-9.]*' | head -1)
  [ -z "$KUBECTL_VERSION" ] && KUBECTL_VERSION="N/A"
  print_info "kubectl Version" "$KUBECTL_VERSION"
  
  CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "N/A")
  print_info "Current Context" "$CURRENT_CONTEXT"
fi


# Summary
printf "\n${blue}╔════════════════════════════════════════╗${no_color}\n"
printf "${blue}║${no_color}         ${green}Diagnostic Complete${no_color}          ${blue}║${no_color}\n"
printf "${blue}╚════════════════════════════════════════╝${no_color}\n\n"

if [ -n "$OUTPUT_FILE" ]; then
  printf "${green}✓${no_color} Report saved to: ${cyan}$OUTPUT_FILE${no_color}\n\n"
fi
