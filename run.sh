#!/bin/bash
# Starts Peekaboo: the data server plus the ghost on screen.
# Closing the ghost (✕, or the menu bar › Quit) stops the server too.
set -euo pipefail
cd "$(dirname "$0")"

export PEEKABOO_PORT="${PEEKABOO_PORT:-8787}"
PIDFILE=".server.pid"
APP="Peekaboo.app/Contents/MacOS/Peekaboo"

# Stop a previous Peekaboo if one is around — including the old
# "companion-app" binary, the name it had before it became Peekaboo.
pkill -f 'Peekaboo.app/Contents/MacOS/Peekaboo' 2>/dev/null || true
pkill -f 'companion-app' 2>/dev/null || true
if [ -f "$PIDFILE" ]; then
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
  rm -f "$PIDFILE"
fi
sleep 0.4

# Rebuild the bundle only when the source has changed.
if [ ! -x "$APP" ] || [ Peekaboo.swift -nt "$APP" ]; then
  ./build.sh
fi

/usr/bin/python3 server.py &
echo $! > "$PIDFILE"
trap 'kill "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null || true; rm -f "$PIDFILE"' EXIT

# Wait for the server to answer before showing the ghost.
ok=0
for _ in $(seq 1 40); do
  if curl -sf "http://127.0.0.1:$PEEKABOO_PORT/api/sessions" >/dev/null 2>&1; then ok=1; break; fi
  sleep 0.15
done
[ "$ok" = 1 ] || { echo "the server is not answering on port $PEEKABOO_PORT"; exit 1; }

echo "👻 Peekaboo is up — port $PEEKABOO_PORT"
"./$APP"
