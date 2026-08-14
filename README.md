# Local Note

Local Note is a small, offline-first macOS menu bar work log. It keeps the
current day available without a browser and can optionally synchronize the
day's outline to a Notion page.

The project is intentionally native and dependency-free:

- status bar icon and popover; no Dock window
- AppKit + SwiftUI; no Electron and no embedded web view
- one JSON file per day; only the selected day is held in memory
- credentials stored in macOS Keychain
- event-driven synchronization; no background polling loop

> Local Note is an independent open-source project and is not affiliated with
> or endorsed by Notion Labs, Inc.

## Project status

Early self-use MVP. Source builds are supported; signed or notarized binaries
are not currently distributed.

## Build requirements

- macOS 11 or newer
- Swift 5.4 or newer Command Line Tools
- no full Xcode installation is required for command-line builds

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/package-app.sh
open build/LocalNote.app
```

With a full Xcode installation, the Swift Package can also be built with
`swift build`. The repository scripts compile directly with `swiftc` so the
self-use workflow works with Command Line Tools alone.

## Outline keyboard interaction

- `Return`: add a peer item;
- `Tab` / `Shift-Tab`: indent or outdent the current item;
- `Backspace`: edit text normally, then remove the row when it is already empty;
- right-click: completion, hierarchy, row type, strikethrough, and delete actions.

## Notion setup

Notion sync is optional. Create your own Notion token, grant it access only to
the page used by Local Note, and enter the token in the app. The token is saved
to Keychain and is never written to the repository or daily JSON files.

Synchronization remains event-driven to keep idle resource use low. It runs
when the popover opens, when the refresh button is pressed, shortly after a
local edit, and when the network becomes available again. Changes made in
Notion while the popover is already open require the refresh button (or closing
and reopening the popover); there is intentionally no background polling.
Online requests normally finish within a few seconds and fail with a visible
error after 15 seconds instead of leaving the status spinning indefinitely.

See [architecture](docs/architecture.md), [implementation plan](docs/implementation-plan.md),
the [test plan](docs/test-plan.md), the measured [performance baseline](docs/performance.md),
and the [app icon rationale](docs/icon-design.md).

## License

MIT
