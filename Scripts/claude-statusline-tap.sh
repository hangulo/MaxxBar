#!/bin/sh
# Claude Code status line command installed by install-claude-statusline-tap.sh.
# Saves the status line JSON (which carries rate_limits) for MaxxBar, then runs the
# previously configured status line command, if any, so its output is unchanged.
DATA_DIR="$HOME/Library/Application Support/MaxxBar"
NEXT_COMMAND_FILE="$DATA_DIR/statusline-next-command"

input="$(cat)"
case "$input" in
    *'"rate_limits"'*)
        mkdir -p "$DATA_DIR"
        tmp="$DATA_DIR/.claude-statusline.$$"
        printf '%s' "$input" > "$tmp" && mv -f "$tmp" "$DATA_DIR/claude-statusline.json"
        ;;
esac

if [ -s "$NEXT_COMMAND_FILE" ]; then
    printf '%s' "$input" | sh -c "$(cat "$NEXT_COMMAND_FILE")"
fi
