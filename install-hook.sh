#!/bin/bash
# Collega l'hook Notification di Claude Code al companion.
# Da quel momento il giallo "aspetta te" e' un segnale certo, non una stima.
#
# Per disinstallare:  ./install-hook.sh --remove
set -euo pipefail
cd "$(dirname "$0")"

HOOK="$(pwd)/hooks/companion-notify.sh"
SETTINGS="$HOME/.claude/settings.json"
MODE="${1:-install}"

cp "$SETTINGS" "$SETTINGS.backup-companion" 2>/dev/null || true

/usr/bin/python3 - "$SETTINGS" "$HOOK" "$MODE" <<'PY'
import json, sys, os

path, hook, mode = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(path)) if os.path.exists(path) else {}
hooks = data.setdefault("hooks", {})
entries = hooks.setdefault("Notification", [])

# Via ogni traccia precedente del companion, cosi' non si accumulano doppioni.
cleaned = []
for entry in entries:
    kept = [h for h in entry.get("hooks", [])
            if "companion-notify" not in str(h.get("command", ""))]
    if kept:
        entry["hooks"] = kept
        cleaned.append(entry)
entries[:] = cleaned

if mode == "--remove":
    if not entries:
        hooks.pop("Notification", None)
    if not hooks:
        data.pop("hooks", None)
    print("hook rimosso")
else:
    entries.append({"hooks": [{"type": "command", "command": hook}]})
    print("hook installato")

json.dump(data, open(path, "w"), indent=2, ensure_ascii=False)
PY

echo "backup: $SETTINGS.backup-companion"
echo "Le sessioni gia' aperte prendono l'hook al prossimo riavvio."
