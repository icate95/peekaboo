<div align="center">

# 👻 Peekaboo

**A desk companion that shows you what your Claude Code sessions are doing.**

A little ghost lives on your desktop and tells you, at a glance, how many
[Claude Code](https://claude.com/claude-code) sessions are running, what each of
them is up to, and — most importantly — which ones are stuck waiting for *you*.

[Install](#install) · [Features](#features) · [Settings](#settings) ·
[How it works](#how-it-works) · [Contributing](#contributing)

</div>

---

## Why

Ten terminals open and no idea which is which. One session is running a build,
another finished twenty minutes ago, and a third has been sitting on a
permission prompt since you walked away from your desk. Finding out means
cycling through every tab.

Peekaboo answers that without you having to look for it.

Everything runs **locally**. No network, no account, no data leaving your Mac:
it only reads the state files Claude Code already writes into `~/.claude`.

---

## What you see

A borderless column, floating above your other windows, taking up the full
height of whichever display you choose. Inside, sessions are **grouped by
project**, one bubble each, every bubble carrying a little ghost in the colour
of its own state:

```
╭─ PEEKABOO ──────────── ●2 ●1 ●14  ☾ ⚙ ✕ ╮
╰──────────────────────────────────────────╯
╭─ donne-di-montagna ───────────────── 2/8 ╮
│  👻 zoho orders      running: sync…   4s │
│  👻 fix products     replied           1h │
╰──────────────────────────────────────────╯
╭─ huniverse-v2 ────────────────────── 1/8 ╮
│  👻 ai next step     waiting for your ok │
╰──────────────────────────────────────────╯
        👻   👻  👻   👻  👻     ← the swarm
              .-""""-.
             / ●    ● \
             |   \__/  |
              \~^~^~^~/
```

Plus a **👻 icon in the menu bar**, with the same list in a dropdown and a count
of the sessions waiting on you.

### The four states

| | State | Meaning |
|---|---|---|
| 🟢 | **working** | thinking, or running a tool |
| 🟡 | **waiting for you** | asked for a permission or an answer, and stopped |
| 🔵 | **replied** | finished, waiting for your next move |
| ⚪️ | **asleep** | idle for more than 45 minutes |

---

## Features

### The wardrobe

The ghost doesn't just change expression — it changes **silhouette**. Every
circumstance gets a different cut:

| Situation | Cut |
|---|---|
| working | slim fit |
| replied | relaxed fit |
| getting bored | puffy |
| bored for a while | ra-ra |
| the window is tall | maxi (with an elastic stretch on the way in) |
| do not disturb | reverse, or invisible |
| **too many sessions on one project** | **three in a trench coat** |

Open `http://127.0.0.1:8787/gallery.html` to see every cut and outfit side by
side, tinted in each state's colours.

### Seasonal outfits

Peekaboo dresses itself according to the calendar:

| Period | Outfit |
|---|---|
| December | Santa hat |
| January → 9 February | winter beanie |
| 10 → 18 February | little hearts |
| late March → early April | bunny ears |
| April → May | flower crown |
| June → August | sunglasses |
| 21 October → 2 November | witch hat |

You can pin one outfit or turn them off entirely in the settings.

### Too many sessions on one project

Past **3 awake sessions** on the same project the box turns pink, the ghost
looks glum, and it puts on the trench coat. It isn't an error — it's a reminder
that beyond that point sessions tend to trip over each other instead of helping.
The threshold is configurable.

### Forgotten sessions

Sessions idle for more than 24 hours get flagged. Hover one and a ✕ appears to
close it (with a confirmation on the second click). Claude gets a SIGTERM, so it
exits cleanly and the transcript survives — you can always pick it back up with
`claude --resume`.

### Click a bubble, get its terminal

Clicking a bubble brings the terminal hosting that session to the front, with
the right tab already selected. Works with **Terminal.app** and **iTerm2**.

The first click makes macOS ask for permission under *System Settings › Privacy
& Security › Automation*. Grant it, or the click does nothing.

### Placement and behaviour

**Which display.** With more than one screen, pick it in the settings — the menu
lists them by name and resolution. Peekaboo lives on **one** of them.

**Arrangement.** Four presets, all on a side column (left or right, your
choice): full column, top half, bottom half, or *free* — drag it anywhere. Move
it by hand and it switches to free automatically; it won't snap back.

**It fades while you work.** When another app is frontmost — that is, when
you're typing somewhere else — the ghost fades out and lets you see through it.
Bring the mouse near and it returns to full. How faint it goes is a 0–100%
slider.

> Detecting *keystrokes* would need the Accessibility permission, the same one a
> keylogger asks for. Which app is frontmost is an equivalent signal that costs
> nothing.

**It's not a box.** The window is still a rectangle — macOS has no other kind —
but clicks **pass straight through** wherever nothing is drawn. You can click
the windows underneath through the empty space around the ghost. The UI reports
its "solid" rectangles to the native shell, which does the filtering.

**The eyes follow your mouse**, wherever it is on screen.

### Microphone and camera

Switch on your microphone and the ghost pulls out a mic and hums along; switch
on your camera and it ends up under the spotlights on a red carpet. Detection
needs **no permission at all**: it asks the system whether the device is running
somewhere, without ever opening a stream.

### Reactions

Click the ghost: if a session is waiting for you, it takes you there. If none
is, it does a somersault and says something.

### Notifications, quiet hours, hotkey

Native macOS notifications when a session starts waiting, optionally when one
replies, and a daily nudge about forgotten sessions — each switchable
separately. The ☾ in the bar turns on **Do Not Disturb** for an hour: no
notifications, no chatter, and the ghost slips into its reverse outfit. It
switches itself back off.

**⌥⌘B** shows or hides the ghost from any app. Any fixed shortcut collides with
something — ⌥⌘G, the obvious choice, belongs to Google Drive — so it is a
setting: pick from ⌥⌘B, ⌥⌘K, ⌥⌘J, ⌥⌘0, ⌃⌥⌘G, ⌃⌥⌘P, or turn it off. Changes take
effect immediately, no restart.

### Themes

Three looks: `soft` (the default rounded style), `pixel` (hard edges, square
eyes) and `minimal` (silhouette only, no face).

---

## Install

You need only things your Mac already has: Python 3 and Swift (via the Xcode
Command Line Tools, `xcode-select --install`).

### From a release

1. Download `Peekaboo.app.zip` from the [latest release](../../releases/latest)
2. Unzip it and drag **Peekaboo.app** into your **Applications** folder
3. Right-click it → **Open** (needed once, because the app is ad-hoc signed
   rather than notarised)

The app is self-contained — it carries its own server and starts it — and ships
as a universal binary, so it runs on both Apple Silicon and Intel Macs.

### From source

```bash
git clone https://github.com/icate95/peekaboo.git
cd peekaboo
./run.sh
```

`run.sh` builds `Peekaboo.app` the first time, starts the local server, and
opens the ghost. To move it out of the project folder afterwards, just drag
`Peekaboo.app` into Applications.

### Commands

| | |
|---|---|
| `./run.sh` | build if needed, then start everything |
| `./build.sh` | rebuild `Peekaboo.app` only |
| `./install-hook.sh` | wire up the hook (see below) |
| `./install-hook.sh --remove` | unwire it |
| `⌥⌘B` | show or hide the ghost (configurable) |

To quit: the ✕ on the bar, or 👻 › Quit in the menu bar. To start it again, open
Peekaboo from Applications or Spotlight — there is no Dock icon, it lives in the
menu bar.

### The hook (recommended)

Without the hook, "waiting for you" is a **guess**: if a tool has been stuck for
over two minutes, Peekaboo assumes there's a permission prompt on screen. That
works, but it's wrong about long commands — builds, test suites, deploys.

Claude Code has a `Notification` hook that fires **exactly** when a session
needs you. Wire it up and the amber becomes a certainty:

```bash
./install-hook.sh
```

It adds one entry to `~/.claude/settings.json`, after saving a copy at
`settings.json.backup-peekaboo`. Sessions already open pick it up when they next
restart.

Guessed bubbles are distinguishable from certain ones — the tooltip says so.
With the hook installed, Peekaboo stops guessing altogether.

---

## Settings

The panel opens with the ⚙. Everything is saved to
`~/Library/Application Support/Peekaboo/settings.json`.

| Setting | What it does |
|---|---|
| Display | which monitor it lives on |
| Arrangement | full column, top half, bottom half, free |
| Side and width | left or right, and how wide |
| Fades out | dims while you work in another app |
| How visible it stays | 0–100% |
| Clicks pass through | click-through wherever nothing is drawn |
| Eyes follow the mouse | on or off |
| Theme | soft, pixel, minimal |
| Outfit | automatic (seasonal), none, or a fixed one |
| Little ghosts around | the swarm |
| Reactions and remarks | somersaults and comments |
| Notifications | one switch each: waiting, replied, forgotten, sound |
| Thresholds | too many sessions, sleeps after, forgotten after |
| Launch when the Mac starts | installs a LaunchAgent |
| Always on top | otherwise it behaves like a normal window |
| Show/hide shortcut | which global hotkey toggles the ghost, or none |

---

## How it works

Claude Code already keeps everything needed in `~/.claude`. Peekaboo only reads
it.

**`~/.claude/sessions/<pid>.json`** — one entry per live session, with `pid`,
`sessionId`, `cwd`, its `status` (`busy` / `idle`), the last-updated timestamp,
and the `name` Claude generates for itself (*"fix products"*, *"ai next step"*).
That name becomes the bubble's title.

**`~/.claude/projects/<project>/<sessionId>.jsonl`** — the full transcript.
Peekaboo reads only the tail (~180 KB) and works out what's happening right now:
if there's a `tool_use` with no matching `tool_result`, the session is running
that tool, and the line becomes *"running: …"*, *"writing config.ts"*,
*"searching «pattern»"*. Otherwise it shows the assistant's last sentence.

**`~/.claude/peekaboo-waiting/<sessionId>.flag`** — written by the hook. Its
presence turns the bubble amber; the server deletes it as soon as the session
gets back to work.

Sessions whose process no longer exists are ignored, so leftover state files
don't clutter the list.

### Architecture

| File | Role |
|---|---|
| `server.py` | Reads `~/.claude`, derives the states, owns the settings, serves the API on `127.0.0.1`. No dependencies outside the standard library. |
| `Peekaboo.swift` | Native shell: borderless transparent window, menu bar item, notifications, global hotkey, device detection. Hosts a `WKWebView`. |
| `ui/index.html` | All the artwork: the ghost in CSS-animated SVG, the swarm, bubbles, settings panel. No external assets, no libraries. |
| `ui/wardrobe.js` | Silhouettes and outfits, shared with the gallery. |
| `ui/gallery.html` | Preview page for every cut and outfit. |
| `build.sh` | Builds `Peekaboo.app` with its Info.plist, icon and an ad-hoc signature. |
| `make-icon.swift` | Draws the app icon and emits an iconset; run by `build.sh`. |
| `hooks/peekaboo-notify.sh` | The `Notification` hook. |

The split has a practical point: **the artwork can be changed without
recompiling**. Edit `ui/index.html`, close and reopen the window, done. Swift is
only rebuilt when `Peekaboo.swift` changes, and `run.sh` notices on its own.

### Why it needs a real `.app`

Without a bundle, system notifications don't work
(`UNUserNotificationCenter` needs a bundle identifier), launch-at-login is
fragile, and the Automation permission gets attributed to the terminal rather
than to Peekaboo — so it would be requested again on every rebuild.

### Security

The server listens on **`127.0.0.1` only**, and the endpoints that act
(`/api/focus`, `/api/close`) accept nothing but pids belonging to a live Claude
session. It is not a channel for running arbitrary commands.

### Why it isn't a macOS widget

WidgetKit widgets redraw as snapshots on a timeline the system decides, usually
every several minutes: no animation, no continuous updates. They also run
sandboxed, so reading `~/.claude` would need entitlements and an app group.
A floating window gives far more for far less scaffolding.

---

## Contributing

The most useful contribution is **feedback on the drawings**. Open
`http://127.0.0.1:8787/gallery.html`, look at the cuts, and open an issue saying
which ones don't read. You don't need to be able to draw — "the puffy one looks
like a flower" is exactly the right level of detail.

### Where to change what

| What | Where |
|---|---|
| State colours | `ui/index.html`, the `:root` block |
| Silhouettes and outfits | `ui/wardrobe.js` |
| Outfit calendar | `ui/wardrobe.js`, `skinForDate()` |
| Face and expressions | `ui/index.html`, the `<svg id="big">` and the `MOUTH` map |
| Things it says | `ui/index.html`, `POKES` and `render()` |
| Default settings | `server.py`, `DEFAULTS` |
| Window geometry | `Peekaboo.swift`, `defaultFrame()` |
| Keyboard shortcut choices | `Peekaboo.swift`, the `HOTKEYS` table |
| Server port | `PEEKABOO_PORT` environment variable (default 8787) |

### Adding a terminal

Terminal focusing lives in `server.py`: add an AppleScript to `TERM_APPS` that
matches a tty and selects the corresponding tab. The hard part is that the
terminal must expose its sessions' tty over AppleScript — Ghostty, WezTerm and
Alacritty currently don't.

---

## Known limitations

- **macOS only.** The shell is AppKit and the focusing is AppleScript. The
  server itself is portable, though: the UI works in any browser at
  `http://127.0.0.1:8787`.
- **Terminal focusing covers Terminal.app and iTerm2.** Elsewhere the bubble
  stays clickable but goes nowhere.
- **Non-interactive sessions** (`claude -p`, background tasks) show up in the
  list but have no terminal to open.
- The signature is **ad-hoc**: fine for local use, but distributing the app
  beyond your own Mac would need a Developer ID signature and Apple
  notarisation.

---

## Credits

The wardrobe idea — a ghost that changes silhouette rather than expression — was
inspired by the "ghost fashion" genre of illustration. Every silhouette here is
drawn from scratch in SVG; none is traced from anyone else's artwork.

## License

MIT — see [LICENSE](LICENSE).
