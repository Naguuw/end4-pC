#!/usr/bin/env bash
# ==============================================================================
# Script: apply-power-profile.sh
# Purpose: Standalone Power Profile Manager with Hardware Thermal Limits
#          - Power Saver: Max 70°C (Boost OFF, EPP balance_power)
#          - Balanced:    Max 80°C (Boost ON, EPP balance_performance, 80°C cap)
#          - Performance: Max 85°C (Boost ON, EPP performance, 85°C cap)
# ==============================================================================

PROFILE="${1:-balanced}"
STATE_FILE="/tmp/quickshell-power-profile"

write_sysfs() {
    local val="$1"
    shift
    for pattern in "$@"; do
        for file in $pattern; do
            if [ -f "$file" ]; then
                if [ -w "$file" ]; then
                    echo "$val" > "$file" 2>/dev/null
                elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
                    echo "$val" | sudo -n tee "$file" >/dev/null 2>&1
                fi
            fi
        done
    done
}

set_cpu_boost() {
    local enable="$1"
    # AMD
    write_sysfs "$enable" "/sys/devices/system/cpu/cpufreq/boost"
    write_sysfs "$enable" "/sys/devices/system/cpu/cpufreq/policy*/boost"
    # Intel (no_turbo: 1=off, 0=on)
    if [ -f "/sys/devices/system/cpu/intel_pstate/no_turbo" ]; then
        local intel_val=$([ "$enable" -eq 1 ] && echo 0 || echo 1)
        write_sysfs "$intel_val" "/sys/devices/system/cpu/intel_pstate/no_turbo"
    fi
}

set_cpu_epp() {
    write_sysfs "$1" "/sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference"
}

set_cpu_governor() {
    write_sysfs "$1" "/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
}

set_gpu_profile() {
    write_sysfs "$1" "/sys/class/drm/card*/device/power_dpm_force_performance_level"
}

apply_ryzenadj() {
    local temp_limit="$1"
    local stapm_limit="$2"
    
    if command -v ryzenadj >/dev/null 2>&1; then
        local args="--tctl-temp=${temp_limit}"
        [ -n "$stapm_limit" ] && args+=" --stapm-limit=${stapm_limit}"
        
        # Try direct (SUID), then sudo -n
        ryzenadj $args >/dev/null 2>&1 || sudo -n ryzenadj $args >/dev/null 2>&1 || true
    fi
}

case "$PROFILE" in
    power-saver|power_saver|powersave|eco)
        # Hardware Thermal limit: Max 70°C, 15W STAPM
        apply_ryzenadj 70 15000

        # CPU settings
        set_cpu_boost 0
        set_cpu_epp "balance_power"
        set_cpu_governor "powersave"
        set_gpu_profile "auto"

        # TLP battery profile trigger
        if command -v tlp >/dev/null 2>&1; then
            sudo -n tlp bat >/dev/null 2>&1 || tlp bat >/dev/null 2>&1 || true
        fi

        echo "power-saver" > "$STATE_FILE"
        ;;

    balanced|balance)
        # Hardware Thermal limit: Max 80°C, 28W STAPM
        apply_ryzenadj 80 28000

        # CPU settings
        set_cpu_boost 1
        set_cpu_epp "balance_performance"
        set_cpu_governor "powersave"
        set_gpu_profile "auto"

        echo "balanced" > "$STATE_FILE"
        ;;

    performance|perf)
        # Hardware Thermal limit: Max 85°C, 45W STAPM
        apply_ryzenadj 85 45000

        # CPU settings
        set_cpu_boost 1
        set_cpu_epp "performance"
        set_cpu_governor "performance"
        set_gpu_profile "auto"

        # TLP AC profile trigger
        if command -v tlp >/dev/null 2>&1; then
            sudo -n tlp ac >/dev/null 2>&1 || tlp ac >/dev/null 2>&1 || true
        fi

        echo "performance" > "$STATE_FILE"
        ;;

    get)
        [ -f "$STATE_FILE" ] && cat "$STATE_FILE" || echo "balanced"
        ;;

    *)
        echo "Usage: $0 {power-saver|balanced|performance|get}"
        exit 1
        ;;
esac
