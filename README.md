<img src="assets/icon-master.svg" alt="UsedPorts" width="96">

# UsedPorts

A SwiftUI macOS app that lists and manages TCP/UDP ports in use on your system.

<img src="assets/UsedPorts-App.png" alt="UsedPorts main window" width="720">

## Install

```sh
brew install usedports/tap/usedports
```

This builds (or pours a prebuilt bottle for) UsedPorts and links it into
`~/Applications`. Because Homebrew installs are not quarantined, there is no
Gatekeeper "Open Anyway" prompt.

## Update

Use **Settings → Updates → Check Now** (then **Update to …**), or from a
terminal:

```sh
brew upgrade usedports
```

## Build

Requirements:
- macOS 14+ (Sonoma)
- Xcode 15+
- `xcodegen` (`brew install xcodegen`)

```sh
xcodegen generate
open UsedPorts.xcodeproj
# Cmd+R
```

Command-line build:
```sh
xcodebuild -project UsedPorts.xcodeproj -scheme UsedPorts -destination 'platform=macOS' build
```

Run the test suite:
```sh
xcodebuild test -project UsedPorts.xcodeproj -scheme UsedPorts -destination 'platform=macOS'
```

## Features

- Menu-bar resident + detail window, sharing the same data
- Per-column sort and filter (numeric range, multi-select, text + regex, time range)
- Global search bar
- Row actions: Kill (SIGTERM/SIGKILL), copy PID/Port/Path, reveal in Finder
- Kill result polling confirms the process actually exited — escalates to SIGKILL if it doesn't
- sudo mode: authenticate once, stays active until the app quits (uses the root helper `uph`)
- Auto/manual refresh toggle

### Menu bar

A compact status item shows pinned ports at a glance:

<img src="assets/UsedPorts-menubar.png" alt="Status item" width="240">

Click it to open the popover — search, pinned section, and the full process tree:

<img src="assets/UsedPorts-popover.png" alt="Menu bar popover" width="360">

## Settings

Every toggle and its scope/behavior is documented in the [Settings reference](docs/SETTINGS.md).

## Architecture

```
App/                — SwiftUI app (UsedPorts target)
  Views/            — SwiftUI views
  ViewModels/       — sort / filter / stream logic
  Domain/           — PortScanner, KillSupervisor, PrivilegeManager, ElevatedHelper
  Infrastructure/   — CommandRunner, LsofParser, PsParser
Shared/             — Models, HelperProtocol (shared by app, helper, tests)
Helper/uph/         — privilege-elevation helper CLI
Tests/              — XCTest unit + integration tests
```

## Operating modes

| Mode | Data source | Privileges |
|---|---|---|
| Normal | Direct `lsof -nP -iTCP -iUDP -F pcuLnPT` | Current user |
| sudo | `osascript ... with administrator privileges` launches the `uph` helper; JSONL IPC | root (held while the app is running) |

## Auto-update

UsedPorts is distributed through Homebrew, so updates go through Homebrew too —
there is no embedded updater framework. When the app detects it was installed
via Homebrew, **Settings → Updates** can check (`brew outdated`) and install
(`brew upgrade usedports`, then relaunch). You can always update from a terminal
with `brew upgrade usedports`.

## Notes

- App Sandbox is disabled (needs to run external commands and signal other PIDs)
- Code signing: ad-hoc, Hardened Runtime on, no notarization (local builds only)

## License

MIT — see [LICENSE](LICENSE).
