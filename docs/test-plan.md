# Test plan

## Regression lesson

The original 20-test suite compiled only `LocalNoteCore`. It could validate
documents, Markdown, persistence, and HTTP request construction, but it never
compiled or rendered `AppModel`, `ContentView`, or the menu command setup. A
green result therefore said nothing about macOS first-responder behavior or
keyboard shortcuts in the status-item popover. The direct test build now
includes those app sources and exercises the real SwiftUI text controls.

The first sync tests also assumed date sections used Markdown headings such as
`## 20260814`. The real Notion page returned a plain date parent, tab-indented
children, and `<empty-block/>` separators. The API request succeeded, so the
old suite and UI reported success even though the selected day decoded as
empty. Regression fixtures now mirror that real response structure, including
empty to-do blocks and Notion's sequential numbered-list markers.

## Unit tests

### Domain and editing

- a new day has no rows and a stable date key;
- add, edit, delete, complete, strike, indent, and outdent preserve ordering;
- indentation cannot become negative or jump more than one level;
- completing a checkbox also strikes the row; unchecking preserves explicit
  user strike intent correctly;
- decoding older files tolerates missing optional fields.

### Persistence

- saving then loading returns an identical document;
- missing day files return an empty document;
- corrupt files produce a recoverable error and are not overwritten;
- filenames are derived from local calendar dates, not UTC rollover;
- loading one day does not enumerate or decode historical day files.

### Markdown

- checkbox, numbered, bullet, and text rows round-trip;
- tabs encode hierarchy and are bounded on decode;
- checked and strikethrough states are preserved;
- Markdown control characters are escaped;
- an empty day produces an empty body;
- plain date parents unindent their Notion children for the local outline;
- `<empty-block/>` separators never become visible rows;
- empty Notion to-do blocks remain empty checkboxes.

### Synchronization

- unchanged documents perform no write;
- local-only edits push;
- remote-only edits pull;
- repeated pulls normalize Notion numbering without false conflicts or writes;
- simultaneous changes produce a conflict and never overwrite;
- duplicate passive triggers do not queue redundant synchronization;
- requests time out instead of leaving the UI in a permanent syncing state;
- 401, 403, 404, 409, 429, and transient 5xx responses map to actionable states;
- authorization headers are present in requests but absent from logs.

## Integration tests

- stubbed HTTP transport validates Notion API paths, methods, headers, and JSON;
- Keychain save/read/delete is tested with a test-only service name;
- a packaged app has `LSUIElement=true` and launches without a Dock window;
- offline launch, edit, quit, and relaunch preserves content.

## UI regression coverage

The test executable renders the real SwiftUI outline in an AppKit window,
makes its `NSTextField` the first responder, dispatches `Command-V` through the
application's Edit menu, and verifies that the paste reaches `AppModel`. This
specifically prevents the menu-bar paste regression that a model-only suite
cannot detect. Release acceptance also includes a manual pass through the real
status-item popover using an isolated data directory.

## Performance and longevity

- create ten years of daily fixture files, then load today without reading the
  other files;
- encode and decode a 2,000-row day without super-linear behavior;
- verify there is no repeating application timer while idle;
- run the release executable and sample idle CPU/RSS manually using `ps` or
  Activity Monitor;
- open and close the popover 200 times and check that retained document and
  view-model counts remain constant.

## Acceptance gate

Before pushing a development branch:

```sh
./scripts/verify.sh
./scripts/performance-smoke.sh
```
