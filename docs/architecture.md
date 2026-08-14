# Architecture

## Product shape

Local Note is a menu bar utility, not a document suite. The process uses an
`NSStatusItem` and an `NSPopover`; the app has no Dock icon and creates no main
window. SwiftUI renders the small popover while AppKit owns the application
lifecycle.

## Component boundaries

```text
StatusItem / Popover
        |
        v
DailyOutlineView <-> AppModel
        |               |
        v               v
DayFileStore       SyncCoordinator
  JSON/day          |          |
                    v          v
                 Keychain   NotionClient
```

### Domain

`DayDocument` contains an ordered, flat pre-order list of `OutlineItem` values.
Each item stores its depth explicitly. This avoids retaining a graph of child
objects and makes encoding, keyboard reordering, and Markdown conversion
linear in the number of visible rows.

### Persistence

Documents are stored under Application Support as one file per day:

```text
LocalNote/days/2026-08-13.json
LocalNote/sync/2026-08-13.json
```

Only the selected day is loaded. Writes use a temporary file followed by an
atomic replacement. Historical growth therefore affects disk usage but not
steady-state memory.

### Notion synchronization

The MVP synchronizes one day to one configured Notion page using the enhanced
Markdown API. A sync snapshot records the last common Markdown and its digest.
Before pushing, the coordinator fetches the remote document:

1. remote equals the base: push local content;
2. local equals the base: accept the remote content;
3. both changed: stop and expose a conflict instead of overwriting either side.

The conflict footer offers two explicit resolutions. "以 Notion 为准" fetches
the latest remote day and replaces only the local day. "以本地为准" first
re-fetches the full page, then replaces only the selected remote date section
with the local day. Neither choice runs without a user click.

If Notion reports a truncated Markdown response, synchronization stops before
any PATCH. Replacing a page from a partial response could otherwise erase
content that was not returned by the API.

Automatic work is event driven: application launch, opening the popover,
local edits after a debounce, manual refresh, and network restoration. There
is no recurring polling timer. A fully quit application synchronizes on its
next launch.

### Secrets

The Notion token is stored as a generic password in macOS Keychain. Page IDs
and preferences may use `UserDefaults`; note content and tokens may not.

## Performance budgets

These are engineering targets, not platform guarantees:

- idle CPU: effectively zero, with no application-owned repeating timer;
- loaded documents: one by default;
- popover width: 420 points, virtualized scrolling for long days;
- network payload: current day only;
- saves: 350 ms debounce and atomic file replacement;
- sync: 3 second debounce and at most one in-flight request;
- external runtime dependencies: zero.

The app must not retain URL responses, historical documents, or finished sync
tasks after completion.
