# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-07-31

First public release.

### Session monitoring

- Reads `~/.claude/sessions/*.json` and the tail of each session transcript to
  derive four states: **working**, **waiting for you**, **replied**, **asleep**
- Shows what each session is actually doing right now — the running tool and its
  target, or the assistant's last sentence
- Groups sessions by project, with worktrees called out
- Ignores sessions whose process is gone, so stale state files don't clutter
- Optional `Notification` hook turns "waiting for you" from a heuristic into a
  certainty; without it, a tool stuck for over two minutes is treated as a
  probable permission prompt

### Interaction

- Click a bubble to bring its terminal window and tab to the front
  (Terminal.app and iTerm2)
- Click the ghost to jump to whichever session is waiting for you
- Flags sessions idle for over 24 hours and closes them on request, with a
  confirmation step; SIGTERM keeps the transcript resumable
- Warns when more than three awake sessions share one project
- Global hotkey **⌥⌘G** to show or hide

### The ghost

- Nine silhouettes that follow the mood, including *three in a trench coat* when
  a project has too many sessions, and an elastic stretch when it goes maxi
- Seven seasonal outfits on a calendar: Santa hat, winter beanie, hearts, bunny
  ears, flower crown, sunglasses, witch hat
- A swarm of little ghosts, one per session, coloured by state — the sleeping
  ones sleep
- Expressions: happy eyes when a session replies, shut eyes when everything is
  quiet
- Three themes: soft, pixel, minimal
- Eyes that follow the mouse anywhere on screen
- Pulls out a microphone when yours is live, and lands on a red carpet under
  spotlights when your camera is — detected without requesting any permission
- `/gallery.html` previews every cut and outfit side by side

### Window

- Borderless, transparent, always on top, on the display of your choice
- Four arrangements: full column, top half, bottom half, free
- Clicks pass through wherever nothing is drawn, so it stops behaving like a box
- Fades out while you work in another app, at an opacity you choose
- Single-instance guard, so launch-at-login can't produce two ghosts

### System

- Self-contained `Peekaboo.app`: carries its own server and starts it, so it can
  live in Applications and open with a double click
- Ships as a universal binary, running on both Apple Silicon and Intel
- Native notifications, switchable per event type
- Do Not Disturb for an hour, with automatic expiry
- Launch at login via LaunchAgent
- Settings persisted in `~/Library/Application Support/Peekaboo/settings.json`

[1.0.0]: https://github.com/icate95/peekaboo/releases/tag/v1.0.0
