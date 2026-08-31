#!/usr/bin/env bash
# ==============================================================================
# Script: setup-power-permissions.sh
# Purpose: Configure systemd-tmpfiles rules so non-root users (in wheel group)
#          can modify CPU boost, EPP, and GPU performance profiles without sudo.
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
    echo "This script requires root privileges to configure /etc/tmpfiles.d/."
    echo "Please run: sudo bash $0"
    exit 1
fi

TMPFILE="/etc/tmpfiles.d/quickshell-power.conf"

echo "Creating $TMPFILE..."
cat << 'EOF' > "$TMPFILE"
# Quickshell Power Optimization Rules (allow wheel group to tune power profiles)
z /sys/devices/system/cpu/cpufreq/boost 0664 root wheel -
z /sys/devices/system/cpu/intel_pstate/no_turbo 0664 root wheel -
z /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference 0664 root wheel -
z /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 0664 root wheel -
z /sys/class/drm/card*/device/power_dpm_force_performance_level 0664 root wheel -
EOF

echo "Applying permissions immediately..."
systemd-tmpfiles --create "$TMPFILE"

echo "Done! CPU frequency and Boost sysfs nodes are now writable by the wheel group."
