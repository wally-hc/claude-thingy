# Changelog

All notable changes to Claude-thingy are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

While the version is 0.x, Claude-thingy is in alpha: config formats and folder layouts can still change between minor versions. Any change that needs you to edit your config or move files is listed under **Changed** with what to do.

## [Unreleased]

### Fixed

- A normal follow-up note on a topic with a waiting question started a new job and left the old one waiting, where it could later resume on its own. The note now answers the waiting job. Starting the topic fresh closes the old question, and stuck waiting jobs are closed on start-up.

### Added

- A dashboard window (Home, Jobs, Topics, Settings) with live job counts, this month's cost, and buttons to open, answer or stop jobs. It opens from a desktop shortcut, the taskbar or a double-click on the tray icon, and reuses the running app instead of starting a second copy.
- An app icon, and tray → **Add desktop shortcut**.
- Continue mode `session`. A project job can start from your latest Claude Code session in that project (or a specific one with `session:<name>`), in a forked copy, so your session isn't changed. Say "pick up where I left off". Claude-thingy lists only file names, dates and sizes in Claude Code's folder for that project, and skips its own sessions. The new `session_max_mb` setting caps how big a session it will load.

## [0.1.0] - 2026-10-31

First alpha release.

### Added

- Hotkey voice notes (default Ctrl+Alt+Shift+J), recorded with ffmpeg and transcribed on your machine with whisper.cpp. There's a beep on start and stop, and recording stops on its own after `max_record_seconds`.
- A dispatcher that turns each note into a job spec (kind, workspace, connectors, connector access, notify channel, model, topic, continue mode). Free keyword rules run first, and one Haiku call fills in the rest only when needed. Each spec records `routed_by`.
- A popup to review and edit the spec before a job starts, plus a dry-run mode and `route-test.ahk` for testing routing without starting jobs.
- Four job kinds: `question`, `connector`, `code` and `plan`.
- Three workspaces:
  - `project:<name>` runs in that folder and opens VS Code.
  - `clone:<owner/repo>` works on a branch and pushes only to your fork.
  - `none` is a chat with read and web tools only.
- Topics with a memory file and one conversation file each. Jobs resume a recent session or pick up from memory.
- MCP connectors from `config/connectors.json`. They're read-only by default (only `read_tools` are allowed), with write access when the note asks for changes. New connectors are saved locally and never installed globally.
- Questions that wait for your answer. Answer from a reply window, with a voice note starting "answer", or let the job continue with its best guess after a set time.
- Notifications by toast, email, or a Slack DM (from you or from a bot).
- A tray menu with a Jobs list (answer waiting jobs, stop running ones, open conversations), the last result, the data folder, connector sign-in, dry run and reload.
- `config/instructions.md` for the assistant's persona and rules.
- Settings: `hotkey`, `max_record_seconds`, `sounds`, `claude_settings`, `branch_prefix` and `data_dir`.

[Unreleased]: ../../compare/v0.1.0...HEAD
[0.1.0]: ../../releases/tag/v0.1.0
