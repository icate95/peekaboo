#!/bin/bash
# Wires the Claude Code Notification hook up to Peekaboo.
# From then on the amber "waiting for you" is a certainty, not a guess.
#
# To uninstall:  ./install-hook.sh --remove
set -euo pipefail
cd "$(dirname "$0")"

HOOK="$(pwd)/hooks/peekaboo-notify.sh"
SETTINGS="$HOME/.claude/settings.json"
MODE="${1:-install}"

cp "$SETTINGS" "$SETTINGS.backup-peekaboo" 2>/dev/null || true

/usr/bin/python3 - "$SETTINGS" "$HOOK" "$MODE" <<'PY'
import json, sys, os

path, hook, mode = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(path)) if os.path.exists(path) else {}
hooks = data.setdefault("hooks", {})
entries = hooks.setdefault("Notification", [])

# Clear every earlier trace, so duplicates don't pile up. "companion-notify"
# is the name the hook had before the project was called Peekaboo, so that
# one needs clearing too.
OLD = ("peekaboo-notify", "companion-notify")
cleaned = []
for entry in entries:
    kept = [h for h in entry.get("hooks", [])
            if not any(o in str(h.get("command", "")) for o in OLD)]
    if kept:
        entry["hooks"] = kept
        cleaned.append(entry)
entries[:] = cleaned

if mode == "--remove":
    if not entries:
        hooks.pop("Notification", None)
    if not hooks:
        data.pop("hooks", None)
    print("hook removed")
else:
    entries.append({"hooks": [{"type": "command", "command": hook}]})
    print("hook installed")

json.dump(data, open(path, "w"), indent=2, ensure_ascii=False)
PY

echo "backup: $SETTINGS.backup-peekaboo"
echo "Sessions already open will pick the hook up when they next restart."
