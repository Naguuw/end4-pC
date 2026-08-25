#!/usr/bin/env bash
# presets.sh - manage shell config presets
# Usage:
#   presets.sh --save <name> [description]
#   presets.sh --remove <name>
#   presets.sh --apply <name>
#   presets.sh --rename <name> <new_name> [description]

CONFIG_DIR="$HOME/.config/illogical-impulse"
CONFIG_FILE="$CONFIG_DIR/config.json"
PRESETS_DIR="$CONFIG_DIR/presets"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWITCHWALL="$SCRIPT_DIR/colors/switchwall.sh"

mkdir -p "$PRESETS_DIR"

die() {
    echo "Error: $*" >&2
    exit 1
}

validate_name() {
    [ -n "$1" ] || die "Missing preset name"
    if [[ ! "$1" =~ ^[^/[:space:]]+$ ]] || [[ "$1" == .* ]]; then
        die "Invalid preset name: '$1'"
    fi
}

require_config() {
    [ -f "$CONFIG_FILE" ] || die "Config not found: $CONFIG_FILE"
    jq -e . "$CONFIG_FILE" > /dev/null 2>&1 || die "Config is not valid JSON: $CONFIG_FILE"
}

# write_with_meta <src> <dst> [description]
# Atomically copies src to dst, stripping _presetMeta and setting the description when non-empty
write_with_meta() {
    local src="$1" dst="$2" desc="$3" tmp="${2}.tmp"
    local filter="del(._presetMeta)"
    [ -n "$desc" ] && filter='del(._presetMeta) | ._presetMeta = {"description": $desc}'
    rm -f "$tmp"
    jq --arg desc "$desc" "$filter" "$src" > "$tmp" 2> /dev/null && mv "$tmp" "$dst" || { rm -f "$tmp"; return 1; }
}

action="$1"
name="$2"
validate_name "$name"
preset_file="$PRESETS_DIR/${name}.json"

case "$action" in
    --save)
        require_config
        write_with_meta "$CONFIG_FILE" "$preset_file" "$3" || die "Failed to save preset '$name'"
        ;;
    --remove)
        [ -f "$preset_file" ] || die "Preset not found: '$name'"
        rm -f "$preset_file"
        ;;
    --apply)
        require_config
        [ -f "$preset_file" ] || die "Preset not found: '$name'"
        jq -e . "$preset_file" > /dev/null 2>&1 || die "Preset is not valid JSON: '$name'"
        jq -s '.[0] * .[1] | del(._presetMeta)' "$CONFIG_FILE" "$preset_file" \
            > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE" \
            || die "Failed to apply preset '$name'"
        "$SWITCHWALL" --noswitch || true
        ;;
    --rename|--edit)
        new_name="$3"
        validate_name "$new_name"
        new_file="$PRESETS_DIR/${new_name}.json"
        [ -f "$preset_file" ] || die "Preset not found: '$name'"
        if [ "$name" != "$new_name" ] && [ -e "$new_file" ]; then
            die "A preset named '$new_name' already exists"
        fi
        if [ $# -ge 4 ]; then
            write_with_meta "$preset_file" "$new_file" "$4" || die "Failed to rename preset '$name'"
        else
            cp "$preset_file" "$new_file" 2> /dev/null || die "Failed to rename preset '$name'"
        fi
        if [ "$name" != "$new_name" ]; then
            rm -f "$preset_file"
        fi
        ;;
    *)
        die "Unknown action: '$action'"
        ;;
esac
