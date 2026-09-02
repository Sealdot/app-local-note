# Local Note

Local Note is a small, offline-first macOS menu bar work log. It keeps the
current day available without a browser and can optionally synchronize the
day's outline to a Notion page.

The project is intentionally native and dependency-free:

- status bar icon and popover; no Dock window
- AppKit + SwiftUI; no Electron and no embedded web view
- one JSON file per day; only the selected day is held in memory
- on-demand monthly calendar overview with contribution-style completion levels
- four paired appearance themes, system/light/dark modes, and six accent colors
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

- long items wrap to as many lines as needed and grow while editing;
- `Up` / `Down`: move to the previous or next item;
- `Return`: split at the caret and focus the right-hand item; at line end, add
  a peer after the current item's descendants;
- `Tab` / `Shift-Tab`: indent or outdent the current item;
- after a top-level checkbox, press `Return` then `Tab` on the empty row to
  create its first numbered child (`1.`);
- type `1. ` at the beginning of an empty row to create a numbered structure;
- `Return` continues numbered rows as `2.`, `3.`, and so on;
- indenting a numbered child again uses alphabetic markers such as `a.`;
- `Backspace` on an empty alphabetic row exits to the next parent-level number
  (for example, empty `b.` becomes `2.`);
- `Backspace` on an empty numbered child returns it to the next parent-level
  checkbox to-do;
- `Shift-Up` / `Shift-Down` or `Shift-click`: select consecutive items;
- drag the mouse or trackpad across rows to select partial or complete lines;
- `Command-C`: copy a cross-row selection with line breaks preserved;
- `Command-Shift-S`: toggle strikethrough for the current item or all selected items;
- `Backspace`: edit text normally, then remove an empty row and return to the previous item;
- `Command-Z` / `Command-Shift-Z`: undo or redo text and outline-structure changes;
- right-click: completion, hierarchy, row type, strikethrough, and delete actions.

## Calendar overview

Use the calendar button in the popover header to review a fixed six-week month.
Days with to-dos are marked, and the accent color becomes darker as more
checkbox to-dos are completed. Selecting a day returns directly to its outline.
The overview reads only its visible 42-day range when opened or changed; normal
outline editing continues to keep only the selected day in memory.

## Appearance

Open Settings and use the Appearance section to follow the system appearance or
force Light or Dark mode. System Native, Paper, Graphite, and Midnight themes
each include paired light and dark palettes. Six curated accent colors update
selection, completed checkboxes, and the calendar completion ramp immediately.
Appearance preferences stay on the current Mac and are never synchronized to
Notion.

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

See the [calendar overview design](docs/calendar-overview.md),
[architecture](docs/architecture.md), [implementation plan](docs/implementation-plan.md),
the [test plan](docs/test-plan.md), the measured [performance baseline](docs/performance.md),
and the [app icon rationale](docs/icon-design.md).

## License

MIT
