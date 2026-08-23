# Appearance themes: phase-one design and acceptance

## Scope

Phase one adds a compact, Raycast-inspired appearance workflow to the existing
440 × 560 point menu-bar popover. It keeps Local Note native and
dependency-free while supporting the P0 theme capabilities selected for the
first release:

- appearance mode: follow system, light, or dark;
- four curated paired themes: System Native, Paper, Graphite, and Midnight;
- six validated accent choices;
- an explicit six-level calendar activity ramp for every resolved theme;
- immediate application, local persistence, and one-click reset.

The selected visual direction is stored at
`docs/assets/theme-appearance-p0-option-1.png`. The implementation follows its
gallery-first hierarchy while preserving the current header, footer, Notion
settings, and native controls.

## Product rules

1. Appearance preferences are device-local `UserDefaults`. They are not note
   content, are never written to daily JSON, and are never sent to Notion.
2. Every theme contains a light and dark palette. Follow-system selects the
   matching palette automatically; forcing light or dark overrides only Local
   Note's popover.
3. Accent changes are immediate and update selection, completed checkboxes,
   focus treatment, and the calendar ramp.
4. Sync success, warning, and error colors remain semantic and are not replaced
   by the accent color. Their text labels remain visible.
5. Unknown or removed persisted values fall back to the default appearance
   rather than preventing launch.
6. Reset restores Follow System + System Native + Blue in one action.

## Settings flow

The existing settings surface gains an Appearance section above Notion:

1. Choose Follow System, Light, or Dark from a native segmented control.
2. Browse the four paired theme previews in a two-column gallery.
3. Select one of six accessible accent swatches.
4. See every choice applied to the full popover immediately.
5. Use Restore Defaults to return to the safe native configuration.

The gallery is intentionally curated. Custom color entry, font and density
controls, background imagery, marketplace themes, and import/export remain out
of scope for phase one.

## Theme token contract

Views consume semantic values rather than palette-specific names:

- background and secondary surface;
- primary, secondary, and completed text;
- separator and focus/selection accent;
- calendar activity levels 0 through 5;
- readable calendar text selected from the resolved cell background.

The AppKit outline text field receives resolved text and insertion-point colors
explicitly so its editing state stays aligned with the SwiftUI shell.

## Acceptance cases

### Persistence and recovery

- A new profile starts with Follow System, System Native, and Blue.
- Changing mode, theme, or accent persists immediately and survives a new
  `AppModel` instance.
- Invalid stored raw values fall back to defaults without crashing.
- Restore Defaults updates the UI and persisted values together.

### Appearance behavior

- Follow System resolves to the supplied system light/dark environment.
- Forced Light and Forced Dark ignore the system scheme.
- Each of the four theme IDs resolves to distinct light and dark palettes.
- All six accents produce six calendar levels and readable high-intensity day
  numbers.
- Changing appearance does not mutate the current document, sync snapshot,
  Notion page ID, or Keychain token.

### UI and accessibility

- Appearance controls render before Notion settings inside the existing
  scrollable settings surface.
- Theme cards and accent swatches expose selected state and descriptive labels
  to assistive technologies.
- Keyboard focus can reach the mode picker, every theme card, every accent, and
  Restore Defaults.
- Selection is communicated by border/check treatment in addition to color.
- Light and dark snapshots fit 440 × 560 points without hiding the persistent
  footer.

### Regression gate

- Existing outline editing, calendar navigation, sync settings, conflict
  controls, packaging, credential scan, and performance smoke tests still pass.
- Release verification runs through `./scripts/verify.sh` and
  `./scripts/performance-smoke.sh` before the branch is pushed.
