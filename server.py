#!/usr/bin/env python3
"""Companion — server locale che legge lo stato delle sessioni Claude Code.

Espone su 127.0.0.1:
  GET /              -> la UI (ui/index.html)
  GET /api/sessions  -> stato di tutte le sessioni vive, raggruppate per progetto
"""

import http.server
import json
import os
import re
import socketserver
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
CLAUDE_DIR = HOME / ".claude"
SESSIONS_DIR = CLAUDE_DIR / "sessions"
PROJECTS_DIR = CLAUDE_DIR / "projects"
WAITING_DIR = CLAUDE_DIR / "companion-waiting"  # scritta dall'hook Notification
UI_DIR = Path(__file__).parent / "ui"

PORT = int(os.environ.get("COMPANION_PORT", "8787"))

# Ripiego usato solo finche' l'hook Notification non e' installato: un tool fermo
# da cosi' tanto e' *probabilmente* un prompt di permesso. Alto di proposito,
# perche' i comandi lunghi (build, test, deploy) non vanno scambiati per attese.
PENDING_TOOL_WAIT_S = 120
# Oltre questo tempo di inattivita' una sessione idle e' considerata "addormentata".
SLEEP_AFTER_S = 45 * 60
# Oltre questo numero di sessioni sveglie sullo stesso progetto si fa confusione.
CROWD_LIMIT = 3

_tail_cache = {}  # sessionId -> (mtime, size, parsed)


def pid_alive(pid):
    try:
        os.kill(pid, 0)
    except (OSError, TypeError):
        return False
    return True


def transcript_path(session_id):
    """Trova il .jsonl del transcript per una sessione."""
    hits = list(PROJECTS_DIR.glob(f"*/{session_id}.jsonl"))
    return hits[0] if hits else None


def read_tail(path, nbytes=180_000):
    """Legge le ultime righe JSON di un transcript, saltando quelle troncate."""
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        size = f.tell()
        f.seek(max(0, size - nbytes))
        chunk = f.read().decode("utf-8", "ignore")
    entries = []
    for line in chunk.split("\n"):
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            entries.append(json.loads(line))
        except ValueError:
            continue  # riga tagliata a meta' dal seek
    return entries


def summarize_tool(block):
    """Frase breve e leggibile per un tool_use in corso."""
    name = block.get("name", "?")
    inp = block.get("input") or {}

    def short(v, n=48):
        v = re.sub(r"\s+", " ", str(v)).strip()
        return v[: n - 1] + "…" if len(v) > n else v

    if name == "Bash":
        return f"esegue: {short(inp.get('description') or inp.get('command', ''))}"
    if name in ("Edit", "Write", "NotebookEdit"):
        return f"scrive {short(os.path.basename(str(inp.get('file_path', ''))), 34)}"
    if name == "Read":
        return f"legge {short(os.path.basename(str(inp.get('file_path', ''))), 34)}"
    if name in ("Grep", "Glob"):
        return f"cerca «{short(inp.get('pattern', ''), 28)}»"
    if name in ("WebFetch", "WebSearch"):
        return f"naviga {short(inp.get('url') or inp.get('query', ''), 34)}"
    if name == "Agent":
        return f"delega: {short(inp.get('description', ''), 34)}"
    if name == "Task":
        return f"task: {short(inp.get('description', ''), 34)}"
    return f"usa {name}"


def last_text(entries):
    """Ultimo testo dell'assistente, per capire di cosa si sta occupando."""
    for e in reversed(entries):
        if e.get("type") != "assistant":
            continue
        for block in reversed(e.get("message", {}).get("content", []) or []):
            if isinstance(block, dict) and block.get("type") == "text":
                txt = re.sub(r"\s+", " ", block.get("text", "")).strip()
                txt = re.sub(r"[#*`_>\[\]]", "", txt)
                if len(txt) > 8:
                    return txt[:110]
    return None


def analyze_transcript(session_id):
    """Ritorna (attivita', tool_pendente, eta_del_tool_pendente_in_s)."""
    path = transcript_path(session_id)
    if not path:
        return None, None, None

    try:
        st = path.stat()
    except OSError:
        return None, None, None

    cached = _tail_cache.get(session_id)
    if cached and cached[0] == st.st_mtime and cached[1] == st.st_size:
        entries = cached[2]
    else:
        try:
            entries = read_tail(path)
        except OSError:
            return None, None, None
        _tail_cache[session_id] = (st.st_mtime, st.st_size, entries)

    if not entries:
        return None, None, None

    # Un tool_use dell'assistente senza il tool_result corrispondente = in corso.
    pending, pending_age = None, None
    answered = set()
    for e in reversed(entries[-60:]):
        if e.get("type") == "user":
            for b in e.get("message", {}).get("content", []) or []:
                if isinstance(b, dict) and b.get("type") == "tool_result":
                    answered.add(b.get("tool_use_id"))
        elif e.get("type") == "assistant":
            blocks = e.get("message", {}).get("content", []) or []
            tools = [
                b for b in blocks
                if isinstance(b, dict) and b.get("type") == "tool_use"
                and b.get("id") not in answered
            ]
            if tools:
                pending = tools[-1]
                pending_age = age_of(e.get("timestamp"))
                break

    if pending is not None:
        return summarize_tool(pending), pending.get("name"), pending_age
    return last_text(entries), None, None


def age_of(iso_ts):
    if not iso_ts:
        return None
    try:
        t = time.strptime(iso_ts.split(".")[0].rstrip("Z"), "%Y-%m-%dT%H:%M:%S")
        return max(0, time.time() - (time.mktime(t) - time.timezone))
    except (ValueError, TypeError):
        return None


_hook_cache = [0.0, False]


def hook_installed():
    """L'hook Notification e' cablato nei settings? (ricontrollato ogni 30s)"""
    if time.time() - _hook_cache[0] < 30:
        return _hook_cache[1]
    found = False
    for name in ("settings.json", "settings.local.json"):
        try:
            raw = (CLAUDE_DIR / name).read_text()
        except OSError:
            continue
        if "companion-notify" in raw:
            found = True
            break
    _hook_cache[0], _hook_cache[1] = time.time(), found
    return found


def waiting_flag(session_id):
    """L'hook Notification tocca un file quando la sessione chiede il tuo input."""
    f = WAITING_DIR / f"{session_id}.flag"
    try:
        return time.time() - f.stat().st_mtime
    except OSError:
        return None


def clear_waiting_flag(session_id):
    """Le hai risposto e sta di nuovo lavorando: la bandierina non serve piu'."""
    try:
        (WAITING_DIR / f"{session_id}.flag").unlink()
    except OSError:
        pass


def tty_of(pid):
    """Il tty su cui gira la sessione, es. /dev/ttys015."""
    try:
        out = subprocess.run(["ps", "-o", "tty=", "-p", str(pid)],
                             capture_output=True, text=True, timeout=3).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None
    if not out or out == "??" or not re.fullmatch(r"[a-z0-9/]+", out):
        return None
    return out if out.startswith("/dev/") else f"/dev/{out}"


TERMINAL_APP = """
tell application "Terminal"
  repeat with w in windows
    repeat with t in tabs of w
      if tty of t is "%s" then
        set selected of t to true
        set frontmost of w to true
        activate
        return "ok"
      end if
    end repeat
  end repeat
  return "notfound"
end tell
"""

ITERM_APP = """
tell application "iTerm"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        if tty of s is "%s" then
          select w
          select t
          select s
          activate
          return "ok"
        end if
      end repeat
    end repeat
  end repeat
  return "notfound"
end tell
"""


TERM_APPS = [("Terminal.app", TERMINAL_APP), ("iTerm.app", ITERM_APP)]


def host_app(pid):
    """Risale i processi padre finche' non trova l'app terminale che ospita la
    sessione. Deterministico, e non rischia di svegliare un'app non aperta."""
    seen = 0
    while pid and pid > 1 and seen < 12:
        seen += 1
        try:
            out = subprocess.run(["ps", "-o", "ppid=,command=", "-p", str(pid)],
                                 capture_output=True, text=True, timeout=3).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return None
        if not out:
            return None
        head, _, cmd = out.partition(" ")
        for marker, script in TERM_APPS:
            if marker in cmd:
                return script
        try:
            pid = int(head)
        except ValueError:
            return None
    return None


def focus_terminal(pid):
    """Porta in primo piano la finestra/tab del terminale che ospita la sessione."""
    tty = tty_of(pid)
    if not tty:
        return False, "sessione senza terminale (background?)"

    script = host_app(pid)
    if not script:
        return False, "terminale non riconosciuto (supportati: Terminal, iTerm2)"

    try:
        r = subprocess.run(["osascript", "-e", script % tty],
                           capture_output=True, text=True, timeout=8)
    except (OSError, subprocess.SubprocessError) as e:
        return False, str(e)
    if r.returncode != 0:
        # Al primo click macOS chiede il permesso in
        # Impostazioni > Privacy e sicurezza > Automazione.
        return False, (r.stderr or "").strip()[:160]
    return r.stdout.strip() == "ok", "tab non trovata"


def project_label(cwd):
    """Nome leggibile del progetto, con il worktree evidenziato se presente."""
    p = Path(cwd)
    parts = p.parts
    if ".claude-worktrees" in parts or "worktrees" in parts:
        key = ".claude-worktrees" if ".claude-worktrees" in parts else "worktrees"
        i = parts.index(key)
        base = parts[i - 1] if i > 0 else p.name
        return f"{base} ⑂ {p.name}"
    return p.name or str(p)


def collect():
    HOOK_INSTALLED = hook_installed()
    sessions = []
    for f in sorted(SESSIONS_DIR.glob("*.json")):
        try:
            d = json.loads(f.read_text())
        except (OSError, ValueError):
            continue

        pid = d.get("pid")
        if not pid_alive(pid):
            continue

        sid = d.get("sessionId", "")
        raw_status = d.get("status", "idle")
        idle_for = max(0, time.time() - d.get("updatedAt", 0) / 1000)

        activity, pending_tool, pending_age = analyze_transcript(sid)
        wait_age = waiting_flag(sid)
        if raw_status == "busy" and wait_age is not None:
            clear_waiting_flag(sid)  # ha ripreso a lavorare
            wait_age = None

        # --- stato finale -------------------------------------------------
        # Giallo certo: l'hook Notification ha segnalato una richiesta esplicita.
        # Giallo stimato: nessun hook installato e un tool e' fermo da troppo.
        guessed = False
        if wait_age is not None and wait_age < 6 * 3600 and raw_status != "busy":
            state = "waiting"
        elif (not HOOK_INSTALLED and raw_status == "busy"
              and pending_age is not None and pending_age > PENDING_TOOL_WAIT_S):
            state = "waiting"
            guessed = True
        elif raw_status == "busy":
            state = "working"
        elif idle_for > SLEEP_AFTER_S:
            state = "sleeping"
        else:
            state = "replied"

        if state == "waiting" and pending_tool:
            activity = f"aspetta il tuo ok su {pending_tool}"
        elif state == "sleeping":
            activity = activity or "in pausa"
        elif not activity:
            activity = "pronta"

        sessions.append({
            "pid": pid,
            "sessionId": sid,
            "name": d.get("name") or f"sessione {pid}",
            "cwd": d.get("cwd", ""),
            "project": project_label(d.get("cwd", "")),
            "kind": d.get("kind", "interactive"),
            "state": state,
            "guessed": guessed,
            "activity": activity,
            "idleFor": round(idle_for),
        })

    # --- raggruppamento per progetto -------------------------------------
    order = {"waiting": 0, "working": 1, "replied": 2, "sleeping": 3}
    groups = {}
    for s in sessions:
        groups.setdefault(s["project"], []).append(s)

    out = []
    for project, items in groups.items():
        items.sort(key=lambda s: (order[s["state"]], s["idleFor"]))
        awake = sum(1 for s in items if s["state"] != "sleeping")
        out.append({
            "project": project,
            "cwd": items[0]["cwd"],
            "sessions": items,
            "awake": awake,
            "crowded": awake > CROWD_LIMIT,
            "rank": min(order[s["state"]] for s in items),
        })
    out.sort(key=lambda g: (g["rank"], g["project"].lower()))

    counts = {k: 0 for k in order}
    for s in sessions:
        counts[s["state"]] += 1

    crowded = [g["project"] for g in out if g["crowded"]]

    # Il fantasmino riflette la cosa piu' urgente in corso.
    if counts["waiting"]:
        mood = "waiting"
    elif crowded:
        mood = "crowded"
    elif counts["working"]:
        mood = "working"
    elif counts["replied"]:
        mood = "replied"
    else:
        mood = "sleeping"

    return {
        "groups": out,
        "counts": counts,
        "mood": mood,
        "total": len(sessions),
        "crowded": crowded,
        "crowdLimit": CROWD_LIMIT,
    }


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass  # niente rumore sul terminale

    def _send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/api/sessions":
            try:
                body = json.dumps(collect()).encode()
            except Exception as e:  # il companion non deve mai morire
                body = json.dumps({"error": str(e), "groups": [], "counts": {},
                                   "mood": "sleeping", "total": 0}).encode()
            return self._send(200, body, "application/json")

        if path in ("/", "/index.html"):
            f = UI_DIR / "index.html"
            if f.exists():
                return self._send(200, f.read_bytes(), "text/html; charset=utf-8")

        self._send(404, b"not found", "text/plain")

    def do_POST(self):
        if self.path.split("?")[0] != "/api/focus":
            return self._send(404, b"not found", "text/plain")

        n = int(self.headers.get("Content-Length") or 0)
        try:
            pid = int(json.loads(self.rfile.read(n) or b"{}").get("pid"))
        except (ValueError, TypeError):
            return self._send(400, b'{"ok":false}', "application/json")

        # Accetta solo pid che appartengono davvero a una sessione Claude viva.
        if not (SESSIONS_DIR / f"{pid}.json").exists() or not pid_alive(pid):
            body = json.dumps({"ok": False, "error": "sessione non attiva"}).encode()
            return self._send(404, body, "application/json")

        ok, err = focus_terminal(pid)
        body = json.dumps({"ok": ok, "error": None if ok else err}).encode()
        self._send(200, body, "application/json")


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    WAITING_DIR.mkdir(parents=True, exist_ok=True)
    try:
        with Server(("127.0.0.1", PORT), Handler) as httpd:
            print(f"companion → http://127.0.0.1:{PORT}", flush=True)
            httpd.serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)
