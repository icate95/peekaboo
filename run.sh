#!/bin/bash
# Avvia Peekaboo: server dei dati + fantasmino sullo schermo.
# Chiudendo il fantasmino (✕ o menu › Esci) si ferma anche il server.
set -euo pipefail
cd "$(dirname "$0")"

export PEEKABOO_PORT="${PEEKABOO_PORT:-8787}"
PIDFILE=".server.pid"
APP="Peekaboo.app/Contents/MacOS/Peekaboo"

# Ferma un Peekaboo precedente, se c'e' — compreso il vecchio binario
# "companion-app", il nome che aveva prima di chiamarsi Peekaboo.
pkill -f 'Peekaboo.app/Contents/MacOS/Peekaboo' 2>/dev/null || true
pkill -f 'companion-app' 2>/dev/null || true
if [ -f "$PIDFILE" ]; then
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
  rm -f "$PIDFILE"
fi
sleep 0.4

# Ricostruisce il bundle solo se il sorgente e' cambiato.
if [ ! -x "$APP" ] || [ Peekaboo.swift -nt "$APP" ]; then
  ./build.sh
fi

/usr/bin/python3 server.py &
echo $! > "$PIDFILE"
trap 'kill "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null || true; rm -f "$PIDFILE"' EXIT

# Aspetta che il server risponda prima di mostrare il fantasmino.
ok=0
for _ in $(seq 1 40); do
  if curl -sf "http://127.0.0.1:$PEEKABOO_PORT/api/sessions" >/dev/null 2>&1; then ok=1; break; fi
  sleep 0.15
done
[ "$ok" = 1 ] || { echo "il server non risponde sulla porta $PEEKABOO_PORT"; exit 1; }

echo "👻 Peekaboo attivo — porta $PEEKABOO_PORT"
"./$APP"
