#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="end4-pC"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

term_alpha=100 #Set this to < 100 make all your terminals transparent
# sleep 0 # idk i wanted some delay or colors dont get applied properly
if [ ! -d "$STATE_DIR"/user/generated ]; then
  mkdir -p "$STATE_DIR"/user/generated
fi
cd "$CONFIG_DIR" || exit

colornames=''
colorstrings=''
colorlist=()
colorvalues=()

colornames=$(cat $STATE_DIR/user/generated/material_colors.scss | cut -d: -f1)
colorstrings=$(cat $STATE_DIR/user/generated/material_colors.scss | cut -d: -f2 | cut -d ' ' -f2 | cut -d ";" -f1)
IFS=$'\n'
colorlist=($colornames)     # Array of color names
colorvalues=($colorstrings) # Array of color values

apply_kitty() {  
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/kitty-theme.conf" ]; then
    echo "Template file not found for Kitty theme. Skipping that."
    return
  fi
  # Copy template
  mkdir -p "$STATE_DIR"/user/generated/terminal
  cp "$SCRIPT_DIR/terminal/kitty-theme.conf" "$STATE_DIR"/user/generated/terminal/kitty-theme.conf
  # Apply colors
  for i in "${!colorlist[@]}"; do
    sed -i "s/${colorlist[$i]} #/${colorvalues[$i]#\#}/g" "$STATE_DIR"/user/generated/terminal/kitty-theme.conf
  done

  # Reload
  pkill -USR1 -x kitty 2>/dev/null || kill -SIGUSR1 $(pidof kitty) 2>/dev/null || true
}

apply_anyterm() {
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/sequences.txt" ]; then
    echo "Template file not found for Terminal. Skipping that."
    return
  fi
  # Copy template
  mkdir -p "$STATE_DIR"/user/generated/terminal
  cp "$SCRIPT_DIR/terminal/sequences.txt" "$STATE_DIR"/user/generated/terminal/sequences.txt
  # Apply colors
  for i in "${!colorlist[@]}"; do
    sed -i "s/${colorlist[$i]} #/${colorvalues[$i]#\#}/g" "$STATE_DIR"/user/generated/terminal/sequences.txt
  done

  sed -i "s/\$alpha/$term_alpha/g" "$STATE_DIR/user/generated/terminal/sequences.txt"

  for file in /dev/pts/*; do
    if [[ $file =~ ^/dev/pts/[0-9]+$ ]]; then
      {
      cat "$STATE_DIR"/user/generated/terminal/sequences.txt >"$file"
      } & disown || true
    fi
  done
}

apply_term_fast() {
  mkdir -p "$STATE_DIR"/user/generated/terminal
  python3 - <<EOF
import os

state_dir = "$STATE_DIR"
script_dir = "$SCRIPT_DIR"
scss_path = f"{state_dir}/user/generated/material_colors.scss"
kitty_template = f"{script_dir}/terminal/kitty-theme.conf"
kitty_out = f"{state_dir}/user/generated/terminal/kitty-theme.conf"
seq_template = f"{script_dir}/terminal/sequences.txt"
seq_out = f"{state_dir}/user/generated/terminal/sequences.txt"

color_map = {}
if os.path.isfile(scss_path):
    with open(scss_path, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith("$") and ":" in line:
                var, val = line.split(":", 1)
                var = var.strip()
                val = val.split(";")[0].strip().lstrip("#")
                color_map[f"{var} #"] = val

if os.path.isfile(kitty_template):
    with open(kitty_template, "r") as f:
        content = f.read()
    for k, v in color_map.items():
        content = content.replace(k, v)
    with open(kitty_out, "w") as f:
        f.write(content)

if os.path.isfile(seq_template):
    with open(seq_template, "r") as f:
        content = f.read()
    for k, v in color_map.items():
        content = content.replace(k, v)
    content = content.replace("\$alpha", "$term_alpha")
    with open(seq_out, "w") as f:
        f.write(content)
EOF

  # Send sequences to open terminals
  if [ -f "$STATE_DIR/user/generated/terminal/sequences.txt" ]; then
    for file in /dev/pts/*; do
      if [[ $file =~ ^/dev/pts/[0-9]+$ ]]; then
        {
        cat "$STATE_DIR"/user/generated/terminal/sequences.txt >"$file"
        } & disown || true
      fi
    done
  fi

  # Reload Kitty
  pkill -USR1 -x kitty 2>/dev/null || kill -SIGUSR1 $(pidof kitty) 2>/dev/null || true
}

apply_term() {
  apply_term_fast
}

apply_qt() {
  sh "$CONFIG_DIR/scripts/kvantum/materialQT.sh"          # generate kvantum theme
  python "$CONFIG_DIR/scripts/kvantum/changeAdwColors.py" # apply config colors
}

# Check if terminal theming is enabled in config
CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
if [ -f "$CONFIG_FILE" ]; then
  enable_terminal=$(jq -r '.appearance.wallpaperTheming.enableTerminal' "$CONFIG_FILE")
  if [ "$enable_terminal" = "true" ]; then
    apply_term
  fi
else
  echo "Config file not found at $CONFIG_FILE. Applying terminal theming by default."
  apply_term
fi

# apply_qt & # Qt theming is already handled by kde-material-colors
