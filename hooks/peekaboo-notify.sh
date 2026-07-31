#!/bin/bash
# Hook Notification di Claude Code.
# Claude lo esegue esattamente quando una sessione ha bisogno di te: richiesta di
# permesso su un tool, oppure attesa di input prolungata. Lasciamo un file-flag
# che Peekaboo legge per accendere la bubble di giallo.
#
# L'hook riceve su stdin un JSON con session_id.

set -euo pipefail

DIR="$HOME/.claude/peekaboo-waiting"
mkdir -p "$DIR"

payload=$(cat)
sid=$(printf '%s' "$payload" | /usr/bin/python3 -c \
  'import json,sys; print(json.load(sys.stdin).get("session_id",""))' 2>/dev/null || true)

[ -n "$sid" ] && touch "$DIR/$sid.flag"

# Le bandierine vecchie non servono piu': tieni pulita la cartella.
find "$DIR" -name '*.flag' -mmin +360 -delete 2>/dev/null || true

exit 0
