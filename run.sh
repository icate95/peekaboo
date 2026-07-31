#!/bin/bash
# Avvia il companion: server dei dati + fantasmino sullo schermo.
# Chiudendo il fantasmino (✕ o menu › Esci) si ferma anche il server.
set -euo pipefail
cd "$(dirname "$0")"

export COMPANION_PORT="${COMPANION_PORT:-8787}"
PIDFILE=".server.pid"

# Ferma un companion precedente, se c'e'.
pkill -f 'companion-app' 2>/dev/null || true
if [ -f "$PIDFILE" ]; then
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
  rm -f "$PIDFILE"
fi
sleep 0.4

# Ricompila solo se il sorgente e' cambiato.
if [ ! -x ./companion-app ] || [ Ghost.swift -nt ./companion-app ]; then
  echo "compilo il guscio nativo…"
  swiftc -O Ghost.swift -o companion-app
fi

/usr/bin/python3 server.py &
echo $! > "$PIDFILE"
trap 'kill "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null || true; rm -f "$PIDFILE"' EXIT

# Aspetta che il server risponda prima di mostrare il fantasmino.
ok=0
for _ in $(seq 1 40); do
  if curl -sf "http://127.0.0.1:$COMPANION_PORT/api/sessions" >/dev/null 2>&1; then ok=1; break; fi
  sleep 0.15
done
[ "$ok" = 1 ] || { echo "il server non risponde sulla porta $COMPANION_PORT"; exit 1; }

echo "👻 companion attivo — porta $COMPANION_PORT"
./companion-app
