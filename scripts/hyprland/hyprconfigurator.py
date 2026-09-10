#!/usr/bin/env -S /bin/sh -c "source $(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate&&exec python -E \"$0\" \"$@\""
import argparse
import json
import os
import re
import tempfile

BOOL_KEYS = {
    "decoration:blur:enabled",
    "decoration:shadow:enabled",
    "animations:enabled",
    "input:numlock_by_default",
    "input:touchpad:natural_scroll",
    "input:touchpad:disable_while_typing",
    "input:touchpad:clickfinger_behavior",
}

ANIM_PRESETS = {
    "fast": """\
hl.curve("pc_wobble", { type = "bezier", points = { {0.15, 1.15}, {0.35, 1.0}  } })
hl.curve("pc_decel",  { type = "bezier", points = { {0.05, 0.9},  {0.1,  1.05} } })
hl.curve("pc_accel",  { type = "bezier", points = { {0.3,  0},    {0.8,  0.15} } })
hl.animation({ leaf = "windowsIn",           enabled = true, speed = 5, bezier = "pc_wobble", style = "slide"     })
hl.animation({ leaf = "windowsOut",          enabled = true, speed = 5, bezier = "pc_accel",  style = "slide"     })
hl.animation({ leaf = "windowsMove",         enabled = true, speed = 5, bezier = "pc_decel",  style = "slide"     })
hl.animation({ leaf = "fadeIn",              enabled = true, speed = 4, bezier = "pc_decel"                       })
hl.animation({ leaf = "fadeOut",             enabled = true, speed = 4, bezier = "pc_accel"                       })
hl.animation({ leaf = "layersIn",            enabled = true, speed = 4, bezier = "pc_decel",  style = "slide"     })
hl.animation({ leaf = "layersOut",           enabled = true, speed = 4, bezier = "pc_accel",  style = "slide"     })
hl.animation({ leaf = "workspaces",          enabled = true, speed = 6, bezier = "pc_decel",  style = "slide"     })
hl.animation({ leaf = "specialWorkspaceIn",  enabled = true, speed = 2, bezier = "pc_wobble", style = "slidevert" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 2, bezier = "pc_accel",  style = "slidevert" })
""",
    "normal": """\
hl.curve("emphasizedDecel", { type = "bezier", points = { {0.05, 0.7},  {0.1,  1}    } })
hl.curve("emphasizedAccel", { type = "bezier", points = { {0.3,  0},    {0.8,  0.15} } })
hl.curve("menu_decel",      { type = "bezier", points = { {0.1,  1},    {0,    1}    } })
hl.curve("menu_accel",      { type = "bezier", points = { {0.52, 0.03}, {0.72, 0.08} } })
hl.curve("stall",           { type = "bezier", points = { {1,    -0.1}, {0.7,  0.85} } })
hl.animation({ leaf = "windowsIn",           enabled = true, speed = 3,   bezier = "emphasizedDecel", style = "popin 80%" })
hl.animation({ leaf = "windowsOut",          enabled = true, speed = 2,   bezier = "emphasizedDecel", style = "popin 90%" })
hl.animation({ leaf = "windowsMove",         enabled = true, speed = 3,   bezier = "emphasizedDecel", style = "slide"     })
hl.animation({ leaf = "fadeIn",              enabled = true, speed = 3,   bezier = "emphasizedDecel"  })
hl.animation({ leaf = "fadeOut",             enabled = true, speed = 2,   bezier = "emphasizedDecel"  })
hl.animation({ leaf = "border",              enabled = true, speed = 10,  bezier = "emphasizedDecel"  })
hl.animation({ leaf = "layersIn",            enabled = true, speed = 2.7, bezier = "emphasizedDecel", style = "popin 93%" })
hl.animation({ leaf = "layersOut",           enabled = true, speed = 2.4, bezier = "menu_accel",      style = "popin 94%" })
hl.animation({ leaf = "fadeLayersIn",        enabled = true, speed = 0.5, bezier = "menu_decel"       })
hl.animation({ leaf = "fadeLayersOut",       enabled = true, speed = 2.7, bezier = "stall"            })
hl.animation({ leaf = "workspaces",          enabled = true, speed = 7,   bezier = "menu_decel",      style = "slide"     })
hl.animation({ leaf = "specialWorkspaceIn",  enabled = true, speed = 2.8, bezier = "emphasizedDecel", style = "slidevert" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 1.2, bezier = "emphasizedAccel", style = "slidevert" })
""",
    "niri": """\
hl.curve("niri_wobble", { type = "bezier", points = { {0.15, 1.15}, {0.35, 1.0}  } })
hl.curve("niri_decel",  { type = "bezier", points = { {0.05, 0.9},  {0.1,  1.05} } })
hl.curve("niri_accel",  { type = "bezier", points = { {0.3,  0},    {0.8,  0.15} } })
hl.animation({ leaf = "windowsIn",           enabled = true, speed = 5, bezier = "niri_wobble", style = "slide"     })
hl.animation({ leaf = "windowsOut",          enabled = true, speed = 5, bezier = "niri_accel",  style = "slide"     })
hl.animation({ leaf = "windowsMove",         enabled = true, speed = 5, bezier = "niri_decel",  style = "slide"     })
hl.animation({ leaf = "fadeIn",              enabled = true, speed = 4, bezier = "niri_decel"                       })
hl.animation({ leaf = "fadeOut",             enabled = true, speed = 4, bezier = "niri_accel"                       })
hl.animation({ leaf = "layersIn",            enabled = true, speed = 4, bezier = "niri_decel",  style = "slide"     })
hl.animation({ leaf = "layersOut",           enabled = true, speed = 4, bezier = "niri_accel",  style = "slide"     })
hl.animation({ leaf = "workspaces",          enabled = true, speed = 6, bezier = "niri_decel",  style = "slidevert" })
hl.animation({ leaf = "specialWorkspaceIn",  enabled = true, speed = 4, bezier = "niri_wobble", style = "slidevert" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 4, bezier = "niri_accel",  style = "slidevert" })
""",
}


def to_lua_value(key, value):
    if key in BOOL_KEYS:
        return "false" if value == "0" else "true"
    try:
        return str(int(value))
    except ValueError:
        pass
    try:
        return str(float(value))
    except ValueError:
        pass
    return f'"{value}"'


def to_lua_line(key, value):
    parts = key.replace(":", ".").split(".")
    val = to_lua_value(key, value)
    inner = f"{{ {parts[-1]} = {val} }}"
    for part in reversed(parts[:-1]):
        inner = f"{{ {part} = {inner} }}"
    return f"hl.config({inner})\n"


def make_marker(key):
    parts = key.replace(":", ".").split(".")

    fragment = " = { ".join(parts[:-1])
    if fragment:
        fragment += " = { " + parts[-1] + " ="
    else:
        fragment = parts[-1] + " ="
    return fragment


def write_atomic(path, content):
    dir_name = os.path.dirname(os.path.abspath(path))
    os.makedirs(dir_name, exist_ok=True)
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=dir_name, delete=False) as f:
            f.write(content)
            tmp_path = f.name
        if os.path.exists(path):
            os.chmod(tmp_path, os.stat(path).st_mode)
        os.replace(tmp_path, path)
    except Exception as e:
        if tmp_path and os.path.exists(tmp_path):
            os.remove(tmp_path)
        raise e


def edit_lua(file_path, set_pairs, reset_keys):
    try:
        with open(file_path) as f:
            lines = f.readlines()
    except FileNotFoundError:
        lines = []

    set_dict   = dict(set_pairs)
    reset_set  = set(reset_keys)
    all_keys   = list(set_dict) + list(reset_set)
    markers    = {k: make_marker(k) for k in all_keys}

    new_lines  = []
    found_keys = set()

    for line in lines:
        matched = None
        for k in all_keys:
            if markers[k] in line:
                matched = k
                break
        if matched is None:
            new_lines.append(line)
        elif matched in reset_set:
            print(f"Removed: {matched}")
        else:
            new_lines.append(to_lua_line(matched, set_dict[matched]))
            found_keys.add(matched)
            print(f"Updated: {to_lua_line(matched, set_dict[matched]).strip()}")

    for k, v in set_dict.items():
        if k not in found_keys:
            new_lines.append(to_lua_line(k, v))
            print(f"Added:   {to_lua_line(k, v).strip()}")

    write_atomic(file_path, "".join(new_lines))


def edit_workspace_layout(file_path, workspace, layout):
    try:
        with open(file_path) as f:
            lines = f.readlines()
    except FileNotFoundError:
        lines = []

    marker = f'workspace = "{workspace}"'
    new_line = f'hl.workspace_rule({{ workspace = "{workspace}", layout = "{layout}" }})\n'

    new_lines = []
    replaced = False
    for line in lines:
        if "workspace_rule" in line and marker in line:
            if replaced:
                print(f"Removed duplicate: {line.strip()}")
                continue
            new_lines.append(new_line)
            replaced = True
            print(f"Updated: {new_line.strip()}")
        else:
            new_lines.append(line)

    if not replaced:
        new_lines.append(new_line)
        print(f"Added:   {new_line.strip()}")

    write_atomic(file_path, "".join(new_lines))


def save_preset(anim_file, preset_name):
    content = ANIM_PRESETS.get(preset_name)
    if not content:
        print(f"Unknown preset '{preset_name}'")
        return
    write_atomic(anim_file, content)
    print(f"Wrote preset '{preset_name}' -> {anim_file}")


def apply_config(config_path, main_file, anim_file, workspace_file):
    config_path = os.path.expanduser(config_path)
    if not os.path.exists(config_path):
        print(f"Config file not found: {config_path}")
        return

    try:
        with open(config_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"Failed to read config JSON: {e}")
        return

    hypr = data.get("hyprland", {})
    if not hypr:
        print("No hyprland section in config")
        return

    set_pairs = []

    dec = hypr.get("decoration", {})
    if "rounding" in dec and dec["rounding"] is not None:
        set_pairs.append(("decoration:rounding", str(dec["rounding"])))
    if "activeOpacity" in dec and dec["activeOpacity"] is not None:
        set_pairs.append(("decoration:active_opacity", str(dec["activeOpacity"])))
    if "inactiveOpacity" in dec and dec["inactiveOpacity"] is not None:
        set_pairs.append(("decoration:inactive_opacity", str(dec["inactiveOpacity"])))

    blur = dec.get("blur", {})
    if "enabled" in blur and blur["enabled"] is not None:
        set_pairs.append(("decoration:blur:enabled", "1" if blur["enabled"] else "0"))
    if "size" in blur and blur["size"] is not None:
        set_pairs.append(("decoration:blur:size", str(blur["size"])))
    if "passes" in blur and blur["passes"] is not None:
        set_pairs.append(("decoration:blur:passes", str(blur["passes"])))

    shadow = dec.get("shadow", {})
    if "enabled" in shadow and shadow["enabled"] is not None:
        set_pairs.append(("decoration:shadow:enabled", "1" if shadow["enabled"] else "0"))

    gen = hypr.get("general", {})
    if "borderSize" in gen and gen["borderSize"] is not None:
        set_pairs.append(("general:border_size", str(gen["borderSize"])))
    if "gapsIn" in gen and gen["gapsIn"] is not None:
        set_pairs.append(("general:gaps_in", str(gen["gapsIn"])))
    if "gapsOut" in gen and gen["gapsOut"] is not None:
        set_pairs.append(("general:gaps_out", str(gen["gapsOut"])))
    if "layout" in gen and gen["layout"] is not None:
        set_pairs.append(("general:layout", str(gen["layout"])))

    anim = hypr.get("animations", {})
    if "enable" in anim and anim["enable"] is not None:
        set_pairs.append(("animations:enabled", "1" if anim["enable"] else "0"))

    inp = hypr.get("input", {})
    if "kbLayout" in inp and inp["kbLayout"] is not None:
        set_pairs.append(("input:kb_layout", str(inp["kbLayout"])))
    if "numlock" in inp and inp["numlock"] is not None:
        set_pairs.append(("input:numlock_by_default", "1" if inp["numlock"] else "0"))
    if "repeatDelay" in inp and inp["repeatDelay"] is not None:
        set_pairs.append(("input:repeat_delay", str(inp["repeatDelay"])))
    if "repeatRate" in inp and inp["repeatRate"] is not None:
        set_pairs.append(("input:repeat_rate", str(inp["repeatRate"])))
    if "followMouse" in inp and inp["followMouse"] is not None:
        set_pairs.append(("input:follow_mouse", str(inp["followMouse"])))

    touchpad = inp.get("touchpad", {})
    if "naturalScroll" in touchpad and touchpad["naturalScroll"] is not None:
        set_pairs.append(("input:touchpad:natural_scroll", "1" if touchpad["naturalScroll"] else "0"))
    if "disableWhileTyping" in touchpad and touchpad["disableWhileTyping"] is not None:
        set_pairs.append(("input:touchpad:disable_while_typing", "1" if touchpad["disableWhileTyping"] else "0"))
    if "clickfingerBehavior" in touchpad and touchpad["clickfingerBehavior"] is not None:
        set_pairs.append(("input:touchpad:clickfinger_behavior", "1" if touchpad["clickfingerBehavior"] else "0"))
    if "scrollFactor" in touchpad and touchpad["scrollFactor"] is not None:
        set_pairs.append(("input:touchpad:scroll_factor", str(touchpad["scrollFactor"])))

    if set_pairs:
        edit_lua(os.path.expanduser(main_file), set_pairs, [])

    anim_preset = anim.get("animation")
    if anim_preset:
        save_preset(os.path.expanduser(anim_file), anim_preset)

    special_layout = gen.get("specialLayout")
    if special_layout:
        edit_workspace_layout(os.path.expanduser(workspace_file), "special:special", special_layout)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--file", default="~/.config/hypr/shellOverrides/main.lua")
    p.add_argument("--set", nargs=2, action="append", metavar=("KEY", "VALUE"))
    p.add_argument("--reset", action="append", metavar="KEY")
    p.add_argument("--workspace-layout", nargs=2, metavar=("WORKSPACE", "LAYOUT"))
    p.add_argument("--workspace-file", default="~/.config/hypr/shellOverrides/workspaces.lua")
    p.add_argument("--anim-preset", metavar="PRESET")
    p.add_argument("--anim-file", default="~/.config/hypr/shellOverrides/animations.lua")
    p.add_argument("--apply-config", metavar="CONFIG_JSON")
    args = p.parse_args()

    if args.apply_config:
        apply_config(args.apply_config, args.file, args.anim_file, args.workspace_file)

    if args.anim_preset:
        save_preset(os.path.expanduser(args.anim_file), args.anim_preset)

    if args.workspace_layout:
        edit_workspace_layout(os.path.expanduser(args.workspace_file), *args.workspace_layout)

    raw_sets   = args.set or []
    reset_keys = args.reset or []
    set_pairs  = []
    for k, v in raw_sets:
        if v == "[[EMPTY]]":
            reset_keys.append(k)
        else:
            set_pairs.append((k, v))

    if set_pairs or reset_keys:
        edit_lua(os.path.expanduser(args.file), set_pairs, reset_keys)
    elif not args.apply_config and not args.anim_preset and not args.workspace_layout:
        print("Error: specify --apply-config, --set, --reset, --anim-preset, or --workspace-layout")