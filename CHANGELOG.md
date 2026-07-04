# Changelog

All notable changes to UsedPorts are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-07-04

An efficiency-focused release — big cuts to CPU and memory churn during idle polling, refreshes, and window/focus changes.

### Performance & efficiency
- **Far fewer subprocesses.** Process details are now fetched in a single `ps` call for the whole list instead of three subprocesses per PID — a burst of new connections used to spawn 100+ short-lived processes per refresh.
- **No wasted work on idle polls.** When a scan returns the same data, the table and menu rebuild is skipped entirely.
- **No spikes on show/hide or app switching.** Toggling the window or switching apps no longer restarts the scanner or forces a rescan; the app drops to a slower cadence when it isn't the active app, and foregrounding shows the cached list and refreshes on the next cycle.
- **Lighter rendering & allocations.** The menu-bar list renders only visible rows; the main table skips its full reload when rows are unchanged; augmentation updates no longer copy the whole entry list.

### Features
- **Dock-free when closed** — closing the window drops UsedPorts to a menu-bar-only app; reopen from the menu bar.
- Every PID (including single-port ones) now shows a `process · pid` header in the menu bar.
- Generic icon for processes without an app icon (CLI tools, daemons), with a setting to toggle it.
- Latest version shown next to the current version in Settings; update checks now run every 3 hours.

### Fixes
- Same-port PID groups no longer swap order between refreshes (now deterministic by PID).
- Security: the privileged helper accepts only SIGTERM/SIGKILL.

**Full Changelog**: https://github.com/UsedPorts/UsedPorts/compare/v0.1.0...v0.1.1

## [0.1.0] - 2026-05-26

First public release. UsedPorts is a native macOS menu-bar app for seeing and
managing which processes are holding your TCP/UDP ports.

### Added
- Menu-bar item and main window sharing the same live data.
- Search across PID, port, and process name.
- Per-column sort and filter: numeric ranges, multi-select, text + regex, time ranges.
- Row actions: Kill (SIGTERM/SIGKILL), copy PID/Port/Path, reveal in Finder.
- Confirmed kills: polls after a kill and escalates to SIGKILL if the process survives.
- sudo mode: authenticate once (via the bundled `uph` helper) to see and kill
  processes you don't own; stays active until the app quits.
- Group by PID to collapse multi-port processes into a parent row.
- Menu-bar popover with pinned ports, status indicators, and the full process tree.
- Auto / manual refresh with configurable foreground and background intervals.
- English and Korean localization.
- In-app updates via Homebrew (check and upgrade from Settings, or `brew upgrade`).
- App version shown in the popover header and the Settings window.

### Install
```sh
brew install UsedPorts/tap/usedports
```

Requires macOS 14 (Sonoma) or later on Apple Silicon.

[0.1.1]: https://github.com/UsedPorts/UsedPorts/releases/tag/v0.1.1
[0.1.0]: https://github.com/UsedPorts/UsedPorts/releases/tag/v0.1.0
