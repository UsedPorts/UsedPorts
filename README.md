# UsedPorts

A SwiftUI macOS app that lists and manages TCP/UDP ports in use on your system.

## Install

### Homebrew (recommended)
```sh
brew tap UsedPorts/tap
brew install --cask usedports
```

### Manual download
Grab the latest `.zip` from the [Releases](https://github.com/UsedPorts/UsedPorts/releases) page, unzip, and move `UsedPorts.app` to `/Applications`.

On first launch, if Gatekeeper blocks the app, right-click → "Open" once to allow it.

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

## Notes

- App Sandbox is disabled (needs to run external commands and signal other PIDs)
- Code signing: ad-hoc, Hardened Runtime on, no notarization (local builds only)
- Gatekeeper may warn on first launch — right-click → Open once to allow it
