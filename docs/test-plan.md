# Test plan

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
- an empty day produces an empty body.

### Synchronization

- unchanged documents perform no write;
- local-only edits push;
- remote-only edits pull;
- simultaneous changes produce a conflict and never overwrite;
- 401, 403, 404, 409, 429, and transient 5xx responses map to actionable states;
- authorization headers are present in requests but absent from logs.

## Integration tests

- stubbed HTTP transport validates Notion API paths, methods, headers, and JSON;
- Keychain save/read/delete is tested with a test-only service name;
- a packaged app has `LSUIElement=true` and launches without a Dock window;
- offline launch, edit, quit, and relaunch preserves content.

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
swift test
swift build -c release
./scripts/performance-smoke.sh
./scripts/package-app.sh
plutil -lint build/LocalNote.app/Contents/Info.plist
codesign --verify build/LocalNote.app
```

