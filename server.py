#!/usr/bin/env python3
"""Peekaboo — local server that reads the state of your Claude Code sessions.

Serves on 127.0.0.1:
  GET  /                 the UI (ui/index.html)
  GET  /api/sessions     every live session, grouped by project
  GET  /api/settings     current settings
  POST /api/settings     save settings (and apply the launch-at-login agent)
  POST /api/focus        bring a session's terminal to the front
  POST /api/close        close a forgotten session
"""

import http.server
import json
import os
import re
import signal
import socketserver
import subprocess
import sys
import time
from pathlib import Path

APP_NAME = "Peekaboo"
BUNDLE_ID = "com.peekaboo.ghost"

HOME = Path.home()
CLAUDE_DIR = HOME / ".claude"
SESSIONS_DIR = CLAUDE_DIR / "sessions"
PROJECTS_DIR = CLAUDE_DIR / "projects"
WAITING_DIR = CLAUDE_DIR / "peekaboo-waiting"   # written by the Notification hook

SUPPORT_DIR = HOME / "Library" / "Application Support" / APP_NAME
SETTINGS_FILE = SUPPORT_DIR / "settings.json"
AGENT_FILE = HOME / "Library" / "LaunchAgents" / f"{BUNDLE_ID}.plist"

UI_DIR = Path(__file__).parent / "ui"
PORT = int(os.environ.get("PEEKABOO_PORT", "8787"))

# Fallback used only until the Notification hook is installed: a tool stuck for
# this long is *probably* a permission prompt. Deliberately generous, so that
# long commands (builds, tests, deploys) aren't mistaken for someone waiting.
PENDING_TOOL_WAIT_S = 120

DEFAULTS = {
    "theme": "soft",                # soft | pixel | minimal
    "skin": "auto",                 # auto (seasonal) | off | outfit name
    "swarm": True,                  # little ghosts floating around the big one
    "personality": True,            # reactions, somersaults, remarks
    "crowdLimit": 3,                # awake sessions on one project before it complains
    "sleepAfterMinutes": 45,        # when an idle session counts as asleep
    "forgottenAfterHours": 24,      # when it counts as forgotten
    "notifications": {
        "waiting": True,            # a session is asking for your input
        "replied": False,           # a session has finished replying
        "forgotten": True,          # sessions have been idle for days
        "sound": True,
    },
    "dndUntil": 0,                  # when do-not-disturb ends (0 = off)
    "autostart": False,
    "alwaysOnTop": True,
    # Any fixed shortcut collides with something, so it is a setting.
    # ⌥⌘G, the original default, belongs to Google Drive on many Macs.
    "hotkey": "opt-cmd-B",          # see HOTKEYS in Peekaboo.swift, or "none"

    # --- window placement and behaviour ---
    "layout": "full",               # full | half | tophalf | free
    "screen": -1,                   # -1 = main display, otherwise an index
    "side": "right",                # right | left
    "width": 340,
    "collapsed": False,             # folded down to the thin rail on the side
    "autoFade": True,               # fades out while you work elsewhere
    "fadeOpacity": 0.32,
    "eyesFollow": True,             # the eyes follow the mouse
    "clickThrough": True,           # clicks pass through wherever nothing is drawn
}

_tail_cache = {}   # sessionId -> (mtime, size, parsed)
_settings = None


# -------------------------------------------------------------------- settings

def deep_merge(base, over):
    """Merges saved settings onto the defaults, without losing newly added keys."""
    out = dict(base)
    for k, v in (over or {}).items():
        if k in out and isinstance(out[k], dict) and isinstance(v, dict):
            out[k] = deep_merge(out[k], v)
        elif k in out:
            out[k] = v
    return out


# Theme names used to be Italian. Settings files written before the rename
# still carry them, so translate on read rather than resetting the user's choice.
RENAMED_THEMES = {"morbido": "soft", "minimale": "minimal"}


def migrate(saved):
    if saved.get("theme") in RENAMED_THEMES:
        saved["theme"] = RENAMED_THEMES[saved["theme"]]
    if saved.get("layout") == "libero":
        saved["layout"] = "free"
    return saved


def load_settings():
    global _settings
    if _settings is None:
        try:
            saved = json.loads(SETTINGS_FILE.read_text())
        except (OSError, ValueError):
            saved = {}
        _settings = deep_merge(DEFAULTS, migrate(saved))
    return _settings


def save_settings(patch):
    global _settings
    _settings = deep_merge(load_settings(), patch)
    SUPPORT_DIR.mkdir(parents=True, exist_ok=True)
    tmp = SETTINGS_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(_settings, indent=2, ensure_ascii=False))
    tmp.replace(SETTINGS_FILE)          # atomic write: never a half-written file
    apply_autostart(_settings["autostart"])
    return _settings


def dnd_active():
    return load_settings().get("dndUntil", 0) > time.time()


# ------------------------------------------------------------ launch at login

def app_bundle_path():
    """The .app this server belongs to, wherever it is.

    Two cases. Running from a checkout, the bundle sits next to this file.
    Running from inside an installed app, this file *is* in the bundle, at
    <App>.app/Contents/Resources/server.py — and the app may well have been
    moved to /Applications, so the checkout path is no help.
    """
    here = Path(__file__).resolve().parent
    if (here.name == "Resources" and here.parent.name == "Contents"
            and here.parent.parent.suffix == ".app"):
        return here.parent.parent

    p = here / f"{APP_NAME}.app"
    return p if p.exists() else None


def apply_autostart(enabled):
    """Writes or removes the LaunchAgent that starts Peekaboo at login."""
    try:
        if not enabled:
            if AGENT_FILE.exists():
                subprocess.run(["launchctl", "unload", str(AGENT_FILE)],
                               capture_output=True, timeout=8)
                AGENT_FILE.unlink()
            return True, ""

        bundle = app_bundle_path()
        target = ([str(bundle / "Contents" / "MacOS" / APP_NAME)] if bundle
                  else ["/bin/bash", str(Path(__file__).parent / "run.sh")])

        AGENT_FILE.parent.mkdir(parents=True, exist_ok=True)
        args = "".join(f"    <string>{a}</string>\n" for a in target)
        AGENT_FILE.write_text(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
            '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            '<plist version="1.0">\n<dict>\n'
            f'  <key>Label</key><string>{BUNDLE_ID}</string>\n'
            f'  <key>ProgramArguments</key>\n  <array>\n{args}  </array>\n'
            '  <key>RunAtLoad</key><true/>\n'
            '  <key>KeepAlive</key><false/>\n'
            '  <key>ProcessType</key><string>Interactive</string>\n'
            '</dict>\n</plist>\n')
        subprocess.run(["launchctl", "unload", str(AGENT_FILE)],
                       capture_output=True, timeout=8)
        subprocess.run(["launchctl", "load", str(AGENT_FILE)],
                       capture_output=True, timeout=8)
        return True, ""
    except (OSError, subprocess.SubprocessError) as e:
        return False, str(e)


# ------------------------------------------------------------------- processes

def pid_alive(pid):
    try:
        os.kill(pid, 0)
    except (OSError, TypeError):
        return False
    return True


def transcript_path(session_id):
    hits = list(PROJECTS_DIR.glob(f"*/{session_id}.jsonl"))
    return hits[0] if hits else None


def read_tail(path, nbytes=180_000):
    """Reads the last JSON lines of a transcript, skipping truncated ones."""
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
            continue    # a line the seek cut in half
    return entries


def summarize_tool(block):
    """A short, readable phrase for a tool call in flight."""
    name = block.get("name", "?")
    inp = block.get("input") or {}

    def short(v, n=48):
        v = re.sub(r"\s+", " ", str(v)).strip()
        return v[: n - 1] + "…" if len(v) > n else v

    if name == "Bash":
        return f"running: {short(inp.get('description') or inp.get('command', ''))}"
    if name in ("Edit", "Write", "NotebookEdit"):
        return f"writing {short(os.path.basename(str(inp.get('file_path', ''))), 34)}"
    if name == "Read":
        return f"reading {short(os.path.basename(str(inp.get('file_path', ''))), 34)}"
    if name in ("Grep", "Glob"):
        return f"searching “{short(inp.get('pattern', ''), 28)}”"
    if name in ("WebFetch", "WebSearch"):
        return f"browsing {short(inp.get('url') or inp.get('query', ''), 34)}"
    if name == "Agent":
        return f"delegating: {short(inp.get('description', ''), 34)}"
    if name == "Task":
        return f"task: {short(inp.get('description', ''), 34)}"
    return f"using {name}"


def last_text(entries):
    """The assistant's last piece of text, to tell what it is up to."""
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
    """Returns (activity, pending_tool, pending_tool_age_in_seconds)."""
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

    # An assistant tool_use with no matching tool_result is still running.
    pending, pending_age = None, None
    answered = set()
    for e in reversed(entries[-60:]):
        if e.get("type") == "user":
            for b in e.get("message", {}).get("content", []) or []:
                if isinstance(b, dict) and b.get("type") == "tool_result":
                    answered.add(b.get("tool_use_id"))
        elif e.get("type") == "assistant":
            blocks = e.get("message", {}).get("content", []) or []
            tools = [b for b in blocks
                     if isinstance(b, dict) and b.get("type") == "tool_use"
                     and b.get("id") not in answered]
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


# ------------------------------------------------------------------------ hook

_hook_cache = [0.0, False]


def hook_installed():
    """Is the Notification hook wired into the settings? (rechecked every 30s)"""
    if time.time() - _hook_cache[0] < 30:
        return _hook_cache[1]
    found = False
    for name in ("settings.json", "settings.local.json"):
        try:
            if "peekaboo-notify" in (CLAUDE_DIR / name).read_text():
                found = True
                break
        except OSError:
            continue
    _hook_cache[0], _hook_cache[1] = time.time(), found
    return found


def waiting_flag(session_id):
    try:
        return time.time() - (WAITING_DIR / f"{session_id}.flag").stat().st_mtime
    except OSError:
        return None


def clear_waiting_flag(session_id):
    """You answered and it is working again: the flag has served its purpose."""
    try:
        (WAITING_DIR / f"{session_id}.flag").unlink()
    except OSError:
        pass


# -------------------------------------------------------------------- terminal

def tty_of(pid):
    """The tty the session runs on, e.g. /dev/ttys015."""
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
    """Walks up the parent processes until it finds the terminal app hosting the
    session. Deterministic, and it never wakes an app that isn't running."""
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
    """Brings the hosting terminal's window and tab to the front."""
    tty = tty_of(pid)
    if not tty:
        return False, "session has no terminal (background?)"
    script = host_app(pid)
    if not script:
        return False, "unrecognised terminal (supported: Terminal, iTerm2)"
    try:
        r = subprocess.run(["osascript", "-e", script % tty],
                           capture_output=True, text=True, timeout=8)
    except (OSError, subprocess.SubprocessError) as e:
        return False, str(e)
    if r.returncode != 0:
        # On the first click macOS asks for permission under
        # Settings > Privacy & Security > Automation.
        return False, (r.stderr or "").strip()[:160]
    return r.stdout.strip() == "ok", "tab not found"


def is_session_pid(pid):
    return (SESSIONS_DIR / f"{pid}.json").exists() and pid_alive(pid)


def close_session(pid):
    """Closes a session with SIGTERM: Claude saves and exits cleanly. The
    transcript stays, so it can always be picked up again with --resume."""
    if not is_session_pid(pid):
        return False, "session is not running"
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError as e:
        return False, str(e)
    return True, ""


# ------------------------------------------------------------------ collection

def project_label(cwd):
    """A readable project name, calling out the worktree when there is one."""
    p = Path(cwd)
    parts = p.parts
    if ".claude-worktrees" in parts or "worktrees" in parts:
        key = ".claude-worktrees" if ".claude-worktrees" in parts else "worktrees"
        i = parts.index(key)
        base = parts[i - 1] if i > 0 else p.name
        return f"{base} ⑂ {p.name}"
    return p.name or str(p)


def collect():
    cfg = load_settings()
    sleep_after = cfg["sleepAfterMinutes"] * 60
    forgotten_after = cfg["forgottenAfterHours"] * 3600
    crowd_limit = cfg["crowdLimit"]
    with_hook = hook_installed()

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
            clear_waiting_flag(sid)     # it went back to work
            wait_age = None

# Certain amber: the Notification hook reported an explicit request.
        # Guessed amber: no hook installed, and a tool has been stuck too long.
        guessed = False
        if wait_age is not None and wait_age < 6 * 3600 and raw_status != "busy":
            state = "waiting"
        elif (not with_hook and raw_status == "busy"
              and pending_age is not None and pending_age > PENDING_TOOL_WAIT_S):
            state = "waiting"
            guessed = True
        elif raw_status == "busy":
            state = "working"
        elif idle_for > sleep_after:
            state = "sleeping"
        else:
            state = "replied"

        if state == "waiting" and pending_tool:
            activity = f"waiting for your OK on {pending_tool}"
        elif state == "sleeping":
            activity = activity or "paused"
        elif not activity:
            activity = "ready"

        sessions.append({
            "pid": pid,
            "sessionId": sid,
            "name": d.get("name") or f"session {pid}",
            "cwd": d.get("cwd", ""),
            "project": project_label(d.get("cwd", "")),
            "kind": d.get("kind", "interactive"),
            "state": state,
            "guessed": guessed,
            "forgotten": state == "sleeping" and idle_for > forgotten_after,
            "activity": activity,
            "idleFor": round(idle_for),
        })

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
            "crowded": awake > crowd_limit,
            "rank": min(order[s["state"]] for s in items),
        })
    out.sort(key=lambda g: (g["rank"], g["project"].lower()))

    counts = {k: 0 for k in order}
    for s in sessions:
        counts[s["state"]] += 1
    forgotten = [s for s in sessions if s["forgotten"]]
    crowded = [g["project"] for g in out if g["crowded"]]

    # The ghost mirrors the most pressing thing going on.
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
        "crowdLimit": crowd_limit,
        "forgotten": len(forgotten),
        "hook": with_hook,
        "dnd": dnd_active(),
        "settings": cfg,
    }


# --------------------------------------------------------------------- server

class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass    # keep the terminal quiet

    def _send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj, code=200):
        self._send(code, json.dumps(obj).encode(), "application/json")

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        try:
            return json.loads(self.rfile.read(n) or b"{}")
        except ValueError:
            return {}

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/api/sessions":
            try:
                return self._json(collect())
            except Exception as e:      # the companion must never die
                return self._json({"error": str(e), "groups": [], "counts": {},
                                   "mood": "sleeping", "total": 0})
        if path == "/api/settings":
            return self._json(load_settings())
        # Static UI files. Plain names inside ui/ only: no traversal,
        # no absolute paths.
        name = "index.html" if path == "/" else path.lstrip("/")
        if re.fullmatch(r"[\w.-]+\.(html|js|css)", name):
            f = UI_DIR / name
            if f.exists():
                kind = {"html": "text/html", "js": "text/javascript",
                        "css": "text/css"}[name.rsplit(".", 1)[1]]
                return self._send(200, f.read_bytes(), f"{kind}; charset=utf-8")
        self._send(404, b"not found", "text/plain")

    def do_POST(self):
        path = self.path.split("?")[0]

        if path == "/api/settings":
            return self._json(save_settings(self._body()))

        if path in ("/api/focus", "/api/close"):
            try:
                pid = int(self._body().get("pid"))
            except (ValueError, TypeError):
                return self._json({"ok": False, "error": "invalid pid"}, 400)
            # Only accept pids that really belong to a live Claude session.
            if not is_session_pid(pid):
                return self._json({"ok": False, "error": "session is not running"}, 404)
            ok, err = (focus_terminal(pid) if path == "/api/focus"
                       else close_session(pid))
            return self._json({"ok": ok, "error": None if ok else err})

        self._send(404, b"not found", "text/plain")


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    WAITING_DIR.mkdir(parents=True, exist_ok=True)
    SUPPORT_DIR.mkdir(parents=True, exist_ok=True)
    load_settings()
    try:
        with Server(("127.0.0.1", PORT), Handler) as httpd:
            print(f"{APP_NAME} → http://127.0.0.1:{PORT}", flush=True)
            httpd.serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)
