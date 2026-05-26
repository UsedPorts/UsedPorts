# Changelog

All notable changes to UsedPorts are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.0]: https://github.com/UsedPorts/UsedPorts/releases/tag/v0.1.0
