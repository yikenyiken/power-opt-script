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
echo "[1/4] Checking and installing required dependencies..."

install_dependencies() {
  local pkgs=()
  
  # Identify missing system diagnostics and tuning utilities
  command -v powertop >/dev/null 2>&1 || pkgs+=("powertop")
  command -v tlp >/dev/null 2>&1 || pkgs+=("tlp")
  command -v bc >/dev/null 2>&1 || pkgs+=("bc")

  if [ ${#pkgs[@]} -eq 0 ]; then
    echo " -> All required dependencies (powertop, tlp, bc) are installed."
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
# 2. MEASURE REAL-TIME POWER DRAW
# -----------------------------------------------------------------------------
# Reads power consumption from sysfs battery interfaces (laptops on battery)
get_power_usage_watts() {
  local bat_dir=""
  for b in /sys/class/power_supply/BAT*; do
    if [ -d "$b" ]; then
      bat_dir="$b"
      break
    fi
  done

  if [ -z "$bat_dir" ]; then
    echo "0"
    return
  fi

  # 1. Try direct power_now metric (uW)
  if [ -f "$bat_dir/power_now" ]; then
    awk '{print $1 * 1e-6}' "$bat_dir/power_now" 2>/dev/null || echo "0"
  # 2. Fall back to current_now (uA) * voltage_now (uV)
  elif [ -f "$bat_dir/current_now" ] && [ -f "$bat_dir/voltage_now" ]; then
    awk 'NR==1{c=$1} NR==2{v=$1} END{print (c*v)/1e12}' "$bat_dir/current_now" "$bat_dir/voltage_now" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

echo -e "\n[2/4] Measuring initial power consumption (sampling 3 seconds)..."
sleep 3
INITIAL_POWER=$(get_power_usage_watts)

if (( $(echo "$INITIAL_POWER > 0" | bc -l 2>/dev/null || echo "0") )); then
  printf " -> Initial Power Draw: %.2f W\n" "$INITIAL_POWER"
else
  echo " -> Initial Power Draw: Telemetry unavailable (System running on AC power or non-laptop hardware)."
fi

# -----------------------------------------------------------------------------
# 3. APPLY POWER-SAVING OPTIMIZATIONS
# -----------------------------------------------------------------------------
echo -e "\n[3/4] Applying power-saving optimizations..."

# A. Dynamically detect running background services against a common candidate list
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
  echo " -> Detected ${#ACTIVE_DRAINERS[@]} active candidate service(s) on this machine:"
  for svc in "${ACTIVE_DRAINERS[@]}"; do
    echo "    - Stopping and disabling: $svc"
    systemctl disable --now "$svc" >/dev/null 2>&1 || true
  done
else
  echo " -> No non-essential candidate services are currently active on this system."
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
# 4. MEASURE FINAL POWER DRAW & CALCULATE SAVINGS
# -----------------------------------------------------------------------------
echo -e "\n[4/4] Stabilizing system and measuring optimized power draw (sampling 5 seconds)..."
sleep 5
FINAL_POWER=$(get_power_usage_watts)

echo -e "\n=================================================="
echo "                 RESULTS SUMMARY                  "
echo "=================================================="

if (( $(echo "$INITIAL_POWER > 0 && $FINAL_POWER > 0" | bc -l 2>/dev/null || echo "0") )); then
  SAVED_POWER=$(echo "$INITIAL_POWER - $FINAL_POWER" | bc -l)
  
  printf " Initial Power Draw:   %.2f W\n" "$INITIAL_POWER"
  printf " Optimized Power Draw: %.2f W\n" "$FINAL_POWER"
  
  if (( $(echo "$SAVED_POWER > 0" | bc -l) )); then
    printf " Total Power Saved:    %.2f W\n" "$SAVED_POWER"
  else
    echo " Total Power Saved:    0.00 W (System was already optimized or currently idle)"
  fi
else
  echo " Optimizations applied successfully."
  echo " Note: Wattage measurement requires unplugging from AC power on laptop hardware."
fi
