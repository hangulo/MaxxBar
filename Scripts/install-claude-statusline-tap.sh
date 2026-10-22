#!/bin/sh
# Points Claude Code's status line at MaxxBar's tap, keeping any existing status line
# command running behind it. Undo with: install-claude-statusline-tap.sh --uninstall
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="$HOME/Library/Application Support/MaxxBar"
TAP="$DATA_DIR/claude-statusline-tap.sh"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

mkdir -p "$DATA_DIR" "$(dirname "$SETTINGS")"
if [ "${1:-}" != "--uninstall" ]; then
    cp "$ROOT_DIR/Scripts/claude-statusline-tap.sh" "$TAP"
    chmod +x "$TAP"
fi

/usr/bin/python3 - "$SETTINGS" "$TAP" "$DATA_DIR/statusline-next-command" "${1:-}" <<'PY'
import json, os, shlex, shutil, sys

settings_path, tap, next_path, mode = sys.argv[1:5]
settings = {}
if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
    shutil.copy2(settings_path, settings_path + ".maxxbar-backup")

tap_command = shlex.quote(tap)
current = settings.get("statusLine") or {}
current_command = current.get("command", "") if isinstance(current, dict) else ""

if mode == "--uninstall":
    previous = open(next_path).read().strip() if os.path.exists(next_path) else ""
    if current_command == tap_command:
        if previous:
            settings["statusLine"] = {**current, "command": previous}
        else:
            settings.pop("statusLine", None)
    if os.path.exists(next_path):
        os.remove(next_path)
    print("Removed MaxxBar status line tap")
else:
    if current_command and current_command != tap_command:
        with open(next_path, "w") as f:
            f.write(current_command)
    settings["statusLine"] = {**(current if isinstance(current, dict) else {}), "type": "command", "command": tap_command}
    print("Claude Code status line now feeds MaxxBar:", tap_command)

with open(settings_path + ".tmp", "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
os.replace(settings_path + ".tmp", settings_path)
PY
