# Implementation plan

## MVP scope

1. Status bar icon opens and closes a compact popover.
2. Today loads instantly from a local JSON file and works offline.
3. Users can add, edit, delete, complete, strike, indent, and outdent rows.
4. Previous and next day navigation loads only the requested file.
5. Optional Notion settings use a user-provided token and page ID.
6. Manual and event-driven sync preserve a base snapshot and detect conflicts.
7. A command-line packaging script creates an ad-hoc signed `.app` without a
   paid Apple developer account.
8. An on-demand month overview marks days with to-dos and visualizes completed
   activity without adding background indexing or polling.

## Deferred work

- public OAuth and a hosted token exchange service
- webhook-driven remote updates
- collaborative or CRDT merging
- signed and notarized public downloads
- attachments, images, and rich inline spans

## Milestones

### M1: Core model and local storage

Codable domain objects, date keys, atomic per-day persistence, Markdown codec,
and unit tests.

### M2: Menu bar interaction

Status item, popover, compact outline rows, date navigation, keyboard-friendly
editing, and settings.

### M3: Notion transport

Keychain access, request construction, remote read/update, debounce, sync state,
and deterministic transport tests.

### M4: packaging and performance QA

Release build, `.app` packaging, ad-hoc signing, idle behavior review, large
history smoke test, and documentation.

### M5: work calendar overview

Fixed six-week month grid, contribution-style completion tiers, on-demand
42-day summary loading, direct date selection, and calendar regression tests.
