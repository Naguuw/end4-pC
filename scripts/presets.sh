#!/usr/bin/env bash
# presets.sh - manage shell config presets
# Usage:
#   presets.sh --save <name> [description]
#   presets.sh --remove <name> [--online|--imported]
#   presets.sh --apply <name> [--online|--imported]
#   presets.sh --rename <name> <new_name> [description]
#   presets.sh --export-zip <name>
#   presets.sh --import-zip <zip_path>

CONFIG_DIR="$HOME/.config/illogical-impulse"
CONFIG_FILE="$CONFIG_DIR/config.json"
LOCAL_PRESETS_DIR="$CONFIG_DIR/presets"
ONLINE_PRESETS_DIR="$HOME/.cache/quickshell/presets"
IMPORTED_PRESETS_DIR="$HOME/.cache/quickshell/presets_imported"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWITCHWALL="$SCRIPT_DIR/colors/switchwall.sh"

mkdir -p "$LOCAL_PRESETS_DIR" "$ONLINE_PRESETS_DIR" "$IMPORTED_PRESETS_DIR"

# Blacklist: General (time/battery/audio/sounds/language/workSafety) + Services (ai/networking/musicRecognition/search/screenRecord/screenSnip/updates/bar.weather) + Hyprland non-styling
# Keep: appearance/background/bar(non-weather)/dock/lock/overview/panelFamily etc. + hyprland.decoration/gaps/animations
# Note: apps/profile/wallpaperSelector are NOT blacklisted here (would make preset look empty) - only General+Services per Settings tabs
BLACKLIST_FILTER='del(._presetMeta)
  | del(.time, .battery, .audio, .sounds, .language, .workSafety)
  | del(.ai, .networking, .musicRecognition, .search, .screenRecord, .screenSnip, .updates)
  | del(.bar.weather)
  | del(.hyprland.input, .hyprland.autostartApps, .hyprland.general.layout)'

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
# Atomically copies src to dst, applying blacklist filter and setting description when non-empty
write_with_meta() {
    local src="$1" dst="$2" desc="$3" tmp="${2}.tmp"
    local filter="$BLACKLIST_FILTER"
    if [ -n "$desc" ]; then
        filter="$BLACKLIST_FILTER | ._presetMeta = {\"description\": \$desc}"
    fi
    rm -f "$tmp"
    jq --arg desc "$desc" "$filter" "$src" > "$tmp" 2> /dev/null && mv "$tmp" "$dst" || { rm -f "$tmp"; return 1; }
}

action="$1"
shift

online=false
imported=false
args=()
for arg in "$@"; do
    if [ "$arg" = "--online" ]; then
        online=true
    elif [ "$arg" = "--imported" ]; then
        imported=true
    else
        args+=("$arg")
    fi
done

name="${args[0]}"
description="${args[1]}"

if [ "$action" = "--import-zip" ]; then
    if [ -z "$name" ]; then
        die "Missing zip path"
    fi
    zip_path="$name"
    if [ ! -f "$zip_path" ]; then
        die "Zip not found: $zip_path"
    fi
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    if command -v unzip >/dev/null 2>&1; then
        unzip -q "$zip_path" -d "$tmpdir"
    else
        python3 -c "import zipfile, sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$zip_path" "$tmpdir"
    fi
    # Find json (first *.json not meta.json)
    json_file=$(find "$tmpdir" -maxdepth 4 -name "*.json" ! -name "meta.json" | head -n1)
    if [ -z "$json_file" ]; then
        die "No preset json in zip"
    fi
    base=$(basename "$json_file" .json)
    # Collect assets from the same folder as the json (images etc, exclude json/meta).
    # Anchoring to the json dir (instead of the zip root) supports flat zips as well
    # as folder-wrapped ones (e.g. Blapples' assets/ layout).
    json_dir=$(dirname "$json_file")
    asset_files=$(find "$json_dir" -maxdepth 1 -type f ! -name "*.json" ! -name "meta.json" -exec basename {} \; | jq -R . | jq -s .)
    asset_cache="$IMPORTED_PRESETS_DIR/assets/$base"
    mkdir -p "$asset_cache"
    # Copy assets to cache (plug-and-play like online presets)
    find "$json_dir" -maxdepth 1 -type f ! -name "*.json" ! -name "meta.json" -exec cp -L {} "$asset_cache/" \; 2>/dev/null || true
    # Rewrite json paths to point to cached assets (reuse online jqFilter Profile.qml:250)
    jq --arg dir "$asset_cache" --argjson files "$asset_files" '
      $files as $files | walk(if type == "string" then ((split("/") | last) as $base | if ($files | index($base)) then ($dir + "/" + $base) else . end) else . end)
      | del(._presetMeta) | ._presetMeta.source = "imported"
    ' "$json_file" | jq "$BLACKLIST_FILTER" > "$IMPORTED_PRESETS_DIR/${base}.json"
    echo "Imported $base to $IMPORTED_PRESETS_DIR/${base}.json with assets in $asset_cache"
    trap - EXIT
    rm -rf "$tmpdir"
    exit 0
fi

validate_name "$name"

if $imported; then
    PRESETS_DIR="$IMPORTED_PRESETS_DIR"
elif $online; then
    PRESETS_DIR="$ONLINE_PRESETS_DIR"
else
    PRESETS_DIR="$LOCAL_PRESETS_DIR"
fi

preset_file="$PRESETS_DIR/${name}.json"

case "$action" in
    --save)
        require_config
        write_with_meta "$CONFIG_FILE" "$preset_file" "$description" || die "Failed to save preset '$name'"
        ;;
    --remove)
        [ -f "$preset_file" ] || die "Preset not found: '$name'"
        rm -f "$preset_file"
        if $online; then
            rm -rf "$ONLINE_PRESETS_DIR/assets/${name}"
        elif $imported; then
            rm -rf "$IMPORTED_PRESETS_DIR/assets/${name}"
        fi
        ;;
    --apply)
        require_config
        [ -f "$preset_file" ] || die "Preset not found: '$name'"
        jq -e . "$preset_file" > /dev/null 2>&1 || die "Preset is not valid JSON: '$name'"
        tmp=$(mktemp)
        jq "$BLACKLIST_FILTER" "$preset_file" > "$tmp" || die "Failed to parse preset '$name'"
        jq -s '.[0] * .[1] | del(._presetMeta)' "$CONFIG_FILE" "$tmp" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE" \
            || { rm -f "$tmp"; die "Failed to apply preset '$name'"; }
        rm -f "$tmp"
        "$SWITCHWALL" --noswitch || true
        ;;
    --rename|--edit)
        new_name="${args[1]}"
        new_desc="${args[2]}"
        validate_name "$new_name"
        new_file="$PRESETS_DIR/${new_name}.json"
        [ -f "$preset_file" ] || die "Preset not found: '$name'"
        if [ "$name" != "$new_name" ] && [ -e "$new_file" ]; then
            die "A preset named '$new_name' already exists"
        fi
        if [ $# -ge 3 ] && [ -n "$new_desc" ]; then
            write_with_meta "$preset_file" "$new_file" "$new_desc" || die "Failed to rename preset '$name'"
        else
            cp "$preset_file" "$new_file" 2> /dev/null || die "Failed to rename preset '$name'"
        fi
        if [ "$name" != "$new_name" ]; then
            rm -f "$preset_file"
        fi
        ;;
    --export-zip)
        [ -f "$preset_file" ] || die "Preset not found: '$name'"
        tmpdir=$(mktemp -d)
        trap 'rm -rf "$tmpdir"' EXIT
        filtered="$tmpdir/${name}.json"
        jq "$BLACKLIST_FILTER" "$preset_file" > "$filtered" || die "Failed to filter preset"

        collect_asset() {
            local src="$1"
            if [ -n "$src" ] && [ -f "$src" ]; then
                cp -L "$src" "$tmpdir/" 2>/dev/null || true
                echo "$(basename "$src")"
            fi
        }

        wallpaper=$(jq -r '.background.wallpaperPath // empty' "$filtered")
        lockwall=$(jq -r '.background.lockWall // empty' "$filtered")
        banner=$(jq -r '.sidebar.bannerImage // empty' "$filtered")
        customImg=$(jq -r '.background.widgets.customImage.path // empty' "$filtered")
        avatar=$(jq -r '.profile.avatarPicture // .profile.avatarPath // empty' "$filtered")

        wallpapers="[]"
        if [ -n "$wallpaper" ] && [ -f "$wallpaper" ]; then
            wallpapers=$(jq -n --arg b "$(basename "$wallpaper")" '[$b]')
        fi

        meta_avatar=""; meta_banner=""; meta_custom=""; meta_lock=""
        [ -n "$wallpaper" ] && collect_asset "$wallpaper" >/dev/null
        if [ -n "$lockwall" ] && [ -f "$lockwall" ]; then meta_lock=$(collect_asset "$lockwall"); fi
        if [ -n "$banner" ] && [ -f "$banner" ]; then meta_banner=$(collect_asset "$banner"); fi
        if [ -n "$customImg" ] && [ -f "$customImg" ]; then meta_custom=$(collect_asset "$customImg"); fi
        if [ -n "$avatar" ] && [ -f "$avatar" ]; then meta_avatar=$(collect_asset "$avatar"); fi

        jq -n --argjson w "$wallpapers" \
              --arg avatar "$meta_avatar" --arg banner "$meta_banner" \
              --arg custom "$meta_custom" --arg lock "$meta_lock" \
              '{preview: "", screenshots: [], wallpapers: $w} + (if $avatar != "" then {avatar: $avatar} else {} end)
               + (if $banner != "" then {banner: $banner} else {} end)
               + (if $custom != "" then {customImage: $custom} else {} end)
               + (if $lock != "" then {lockWall: $lock} else {} end)' > "$tmpdir/meta.json"

        zip_name="${name}.zip"
        if command -v zip >/dev/null 2>&1; then
            (cd "$tmpdir" && zip -r "$LOCAL_PRESETS_DIR/$zip_name" . >/dev/null)
        else
            python3 -c "import zipfile, pathlib, sys; z=zipfile.ZipFile(sys.argv[1],'w',zipfile.ZIP_DEFLATED); [z.write(str(p), arcname=p.name) for p in pathlib.Path(sys.argv[2]).iterdir()]; z.close()" "$LOCAL_PRESETS_DIR/$zip_name" "$tmpdir"
        fi
        echo "Exported $LOCAL_PRESETS_DIR/$zip_name"
        trap - EXIT
        rm -rf "$tmpdir"
        ;;
    *)
        die "Unknown action: '$action'"
        ;;
esac
