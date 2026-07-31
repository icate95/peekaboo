#!/bin/bash
# Claude Code Notification hook.
#
# Claude runs this exactly when a session needs you: a tool asking for
# permission, or a long wait for input. We leave a flag file behind, which
# Peekaboo reads to turn that session's bubble amber.
#
# The hook receives JSON on stdin, containing session_id.

set -euo pipefail

DIR="$HOME/.claude/peekaboo-waiting"
mkdir -p "$DIR"

payload=$(cat)
sid=$(printf '%s' "$payload" | /usr/bin/python3 -c \
  'import json,sys; print(json.load(sys.stdin).get("session_id",""))' 2>/dev/null || true)

[ -n "$sid" ] && touch "$DIR/$sid.flag"

# Old flags are of no use: keep the folder tidy.
find "$DIR" -name '*.flag' -mmin +360 -delete 2>/dev/null || true

exit 0
