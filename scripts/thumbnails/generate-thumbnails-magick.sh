#!/usr/bin/env bash

# Generate thumbnails for files (images & videos) using ImageMagick and FFmpeg
# Usage:
#   ./generate-thumbnails-magick.sh --file <path> [--size <normal|large|x-large|xx-large>] [--machine_progress]
#   ./generate-thumbnails-magick.sh --directory <path> [--size <normal|large|x-large|xx-large>] [--machine_progress]

set -e

# Thumbnail sizes mapping
get_thumbnail_size() {
    case "$1" in
        normal) echo 128 ;;
        large) echo 256 ;;
        x-large) echo 512 ;;
        xx-large) echo 1024 ;;
        *) echo 256 ;;
    esac
}

usage() {
    echo "Usage: $0 (--file <path> | --directory <path>) [--size <size>] [--machine_progress]"
    exit 1
}

md5() {
    # Calculate md5 hash of the file's absolute path
    echo -n "$1" | md5sum | awk '{print $1}'
}

urlencode() {
    # Percent-encode a string for use in a URI, but do not encode slashes
    local str="$1"
    local encoded=""
    local c
    for ((i=0; i<${#str}; i++)); do
        c="${str:$i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]|/|'('|')'|'*') encoded+="$c" ;;
            *) printf -v hex '%%%02X' "'${c}'"; encoded+="$hex" ;;
        esac
    done
    echo "$encoded"
}

is_video() {
    local ext="${1##*.}"
    ext="${ext,,}"
    case "$ext" in
        mp4|webm|mkv|avi|mov|flv|wmv) return 0 ;;
        *) return 1 ;;
    esac
}

is_image() {
    local ext="${1##*.}"
    ext="${ext,,}"
    case "$ext" in
        jpg|jpeg|png|webp|avif|bmp|svg|tif|tiff) return 0 ;;
        *) return 1 ;;
    esac
}

VIDEO_THUMBNAIL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/custom/scripts/mpvpaper_thumbnails"

generate_thumbnail() {
    local src="$1"
    local abs_path
    abs_path="$(realpath "$src" 2>/dev/null || echo "$src")"
    [ -f "$abs_path" ] || return 0

    local encoded_path
    encoded_path="$(urlencode "$abs_path")"
    local uri="file://$encoded_path"
    local hash
    hash="$(md5 "$uri")"
    local out="$CACHE_DIR/$hash.png"
    mkdir -p "$CACHE_DIR"

    if is_video "$abs_path"; then
        if command -v ffmpeg &>/dev/null; then
            mkdir -p "$VIDEO_THUMBNAIL_DIR"
            local vid_basename
            vid_basename="$(basename "$abs_path")"
            local vid_thumb="$VIDEO_THUMBNAIL_DIR/${vid_basename}.jpg"
            
            # Generate thumbnail frame for mpvpaper / quickshell
            if [ ! -f "$vid_thumb" ]; then
                ffmpeg -y -ss 00:00:01 -i "$abs_path" -vframes 1 -q:v 2 "$vid_thumb" &>/dev/null || \
                ffmpeg -y -i "$abs_path" -vframes 1 -q:v 2 "$vid_thumb" &>/dev/null || true
            fi

            # Also generate freedesktop cached png if possible
            if [ -f "$vid_thumb" ] && [ ! -f "$out" ]; then
                magick "$vid_thumb" -resize "${THUMBNAIL_SIZE}x${THUMBNAIL_SIZE}" "$out" 2>/dev/null || true
            fi
        fi
    elif is_image "$abs_path"; then
        if [ ! -f "$out" ]; then
            magick "$abs_path" -resize "${THUMBNAIL_SIZE}x${THUMBNAIL_SIZE}" "$out" 2>/dev/null || true
        fi
    fi
}

# Parse arguments
SIZE_NAME="large"
MODE=""
TARGET=""
MACHINE_PROGRESS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --file|-f)
            MODE="file"
            TARGET="$2"
            shift 2
            ;;
        --directory|-d)
            MODE="dir"
            TARGET="$2"
            shift 2
            ;;
        --size|-s)
            SIZE_NAME="$2"
            shift 2
            ;;
        --machine_progress)
            MACHINE_PROGRESS=true
            shift
            ;;
        *)
            usage
            ;;
    esac
done

THUMBNAIL_SIZE="$(get_thumbnail_size "$SIZE_NAME")"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/thumbnails/$SIZE_NAME"

if [ -z "$MODE" ] || [ -z "$TARGET" ]; then
    usage
fi

case "$MODE" in
    file)
        if [ ! -f "$TARGET" ]; then
            echo "File not found: $TARGET"
            exit 2
        fi
        generate_thumbnail "$TARGET"
        if [ "$MACHINE_PROGRESS" = true ]; then
            echo "PROGRESS 1/1 FILE $(realpath "$TARGET")"
        fi
        ;;
    dir)
        if [ ! -d "$TARGET" ]; then
            echo "Directory not found: $TARGET"
            exit 2
        fi

        files=()
        for f in "$TARGET"/*; do
            [ -f "$f" ] || continue
            if is_video "$f" || is_image "$f"; then
                files+=("$f")
            fi
        done

        total=${#files[@]}
        if [ "$total" -eq 0 ]; then
            exit 0
        fi

        current=0
        for f in "${files[@]}"; do
            generate_thumbnail "$f"
            current=$((current + 1))
            if [ "$MACHINE_PROGRESS" = true ]; then
                echo "PROGRESS $current/$total FILE $(realpath "$f")"
            fi
        done
        ;;
    *)
        usage
        ;;
esac

