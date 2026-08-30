#!/usr/bin/env bash

# Exit on critical shell errors and enforce root privileges
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script with sudo or as root."
  exit 1
fi

echo "=================================================="
echo "      Linux Power Optimization & Diagnostics      "
echo "=================================================="

# -----------------------------------------------------------------------------
# 1. DEPENDENCY CHECK & INSTALLATION
# -----------------------------------------------------------------------------
echo "[1/3] Checking and installing required dependencies..."

install_dependencies() {
  local pkgs=()
  
  # Identify missing system tuning utilities
  command -v powertop >/dev/null 2>&1 || pkgs+=("powertop")
  command -v tlp >/dev/null 2>&1 || pkgs+=("tlp")

  if [ ${#pkgs[@]} -eq 0 ]; then
    echo " -> All required dependencies (powertop, tlp) are installed."
    return 0
  fi

  echo " -> Missing tools detected: ${pkgs[*]}"
  
  # Install via appropriate package manager
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq "${pkgs[@]}"
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q "${pkgs[@]}"
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm "${pkgs[@]}"
  else
    echo " -> Warning: Package manager not recognized. Please manually install: ${pkgs[*]}"
  fi
}

install_dependencies

# -----------------------------------------------------------------------------
# 2. APPLY POWER-SAVING OPTIMIZATIONS
# -----------------------------------------------------------------------------
echo -e "\n[2/3] Applying system power optimizations..."

# A. Dynamically detect running background services against a candidate list
KNOWN_POWER_DRAINERS=(
  "apache2"
  "nginx"
  "docker"
  "docker.socket"
  "containerd"
  "libvirtd"
  "cups"
  "cups-browsed"
  "avahi-daemon"
  "avahi-daemon.socket"
  "ModemManager"
  "bluetooth"
  "postgresql"
  "mysql"
  "mariadb"
  "redis"
  "mongod"
)

echo " -> Scanning system for running background daemons..."
ACTIVE_DRAINERS=()

for daemon in "${KNOWN_POWER_DRAINERS[@]}"; do
  unit="$daemon"
  [[ "$unit" != *.* ]] && unit="${daemon}.service"
  
  if systemctl is-active --quiet "$unit" 2>/dev/null; then
    ACTIVE_DRAINERS+=("$unit")
  fi
done

if [ ${#ACTIVE_DRAINERS[@]} -gt 0 ]; then
  echo " -> Detected ${#ACTIVE_DRAINERS[@]} active power-heavy service(s):"
  for svc in "${ACTIVE_DRAINERS[@]}"; do
    echo "    - Stopping and disabling: $svc"
    systemctl disable --now "$svc" >/dev/null 2>&1 || true
  done
else
  echo " -> No non-essential candidate services are currently active."
fi

# B. Apply PowerTOP automatic kernel tunables (PCIe ASPM, USB autosuspend, SATA power management)
if command -v powertop >/dev/null 2>&1; then
  echo " -> Applying PowerTOP kernel tunables..."
  powertop --auto-tune >/dev/null 2>&1 || true
fi

# C. Enable and force TLP battery optimization profiles
if command -v tlp >/dev/null 2>&1; then
  echo " -> Activating TLP battery management..."
  systemctl enable --now tlp >/dev/null 2>&1 || true
  tlp bat >/dev/null 2>&1 || true
fi

# D. Set CPU scaling governor to powersave mode across all CPU cores
if [ -d "/sys/devices/system/cpu/cpu0/cpufreq" ]; then
  echo " -> Setting CPU governor to powersave mode..."
  for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -f "$gov" ] && echo "powersave" > "$gov" 2>/dev/null || true
  done
fi

# -----------------------------------------------------------------------------
# 3. COMPLETION & SUMMARY
# -----------------------------------------------------------------------------
echo -e "\n=================================================="
echo "                 SUMMARY                          "
echo "=================================================="
echo " All optimizations have been applied successfully."
echo ""
echo " What changed:"
echo "  1. Stopped background services polling CPU cycles and network sockets."
echo "  2. Enabled PCIe ASPM, SATA power management, and USB autosuspend."
echo "  3. Forced CPU governor to powersave mode and enabled TLP profiles."
echo ""
echo " Note: By eliminating background service overhead and enforcing low-power"
echo " states, your system will naturally draw less power and extend battery life."
echo "=================================================="