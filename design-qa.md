# Design QA: P0 appearance themes

- Source visual truth: `docs/assets/theme-appearance-p0-option-1.png`
- Implementation screenshot: `docs/assets/theme-p0-settings-system-light.png`
- Combined comparison: `docs/assets/theme-p0-settings-comparison.png`
- Supporting states:
  - `docs/assets/theme-p0-settings-midnight-dark.png`
  - `docs/assets/theme-p0-outline-midnight-dark.png`
  - `docs/assets/theme-p0-calendar-paper-light.png`
- State: Settings open; Follow System; System Native theme; Blue accent;
  synthetic local data; Notion not configured.
- Viewport: native macOS popover content at 440 × 560 points.
- Source dimensions: 1111 × 1416 pixels.
- Implementation dimensions: 880 × 1120 pixels at 2× density.
- Density normalization: the full source was scaled to the 880 × 1120
  implementation panel in the combined comparison. The normalized comparison
  is 1784 × 1120 pixels, including a 24-pixel center gap.

## Findings

No actionable P0, P1, or P2 differences remain.

The implementation intentionally keeps two existing product constraints that
the generated visual did not model precisely:

- theme previews explicitly show each theme's paired light and dark palettes;
  this makes Follow System behavior legible instead of presenting each theme as
  a single fixed appearance;
- add and sync footer actions stay hidden while Settings is open, preserving
  Local Note's existing settings behavior and preventing unrelated actions from
  competing with appearance controls.

## Full-view comparison evidence

The generated target and implementation share the same gallery-first hierarchy:
native header, Appearance heading, three-way appearance selector, two-column
four-theme gallery, six accent swatches, Restore Defaults, and persistent sync
footer. The implementation preserves the target's compact 440-point canvas,
keeps the visual controls above the fold, and leaves Notion settings available
by scrolling rather than shrinking the theme gallery.

## Focused-region comparison evidence

The combined image keeps the appearance controls readable at the normalized
size, so a separate crop was unnecessary. Theme-card selection uses both a
two-point accent border and a checkmark. Accent selection uses a separate outer
ring. Restore Defaults uses a disabled secondary-text state when preferences
already match the default.

## Required fidelity surfaces

- Fonts and typography: both source and implementation use native macOS Chinese
  system typography. Heading, caption, segmented-control, theme-label, and
  footer weights preserve the target hierarchy without custom fonts.
- Spacing and layout rhythm: 24-point settings margins, 12-point gallery gaps,
  104-point previews, and the scroll boundary match the selected composition
  without clipping the fixed footer.
- Colors and visual tokens: four paired palettes, six accents, completed text,
  separators, selection, and six calendar levels resolve through semantic
  theme tokens. High-intensity calendar text is contrast-tested at 4.5:1 or
  higher.
- Image quality and asset fidelity: the design contains no product imagery,
  logos, or decorative raster assets. Runtime previews use native SwiftUI
  controls and SF Symbols so they remain sharp at 2× density. The selected
  Image Gen frame is retained only as design evidence.
- Copy and content: visible labels match the approved Chinese copy: 外观、跟随系统、
  浅色、深色、主题、系统原生、纸张、石墨、午夜、强调色、恢复默认 and
  未配置 Notion.
- Accessibility and interaction: theme and accent buttons expose descriptive
  labels and selected values; selection is not communicated by color alone;
  high-intensity day text contrast is tested; all appearance changes persist
  immediately and Restore Defaults updates the full preference set.

## Interaction verification

- Follow System resolves from the supplied system color scheme.
- Forced Light and Dark override that scheme.
- Theme and accent changes persist immediately in isolated `UserDefaults`.
- Unknown stored raw values fall back safely.
- Appearance changes do not mutate note content or Notion settings.
- Existing outline keyboard, Notion settings, calendar, and sync interaction
  tests remain green.
- Browser console checks are not applicable to this native AppKit/SwiftUI app.

## Comparison history

1. Initial implementation pass: P2 — preview cards were substantially shorter
   than the selected gallery, every unselected accent looked ringed, Restore
   Defaults appeared active in the default state, and the fixture showed Light
   rather than Follow System. Fixed by increasing cards to 104 points, adding
   miniature native headers, simplifying unselected swatches, applying a true
   disabled reset state, and matching the fixture mode.
2. Revised pass: the normalized side-by-side comparison confirmed the corrected
   hierarchy, card proportions, selected states, accent treatment, and copy.
   No actionable P0/P1/P2 differences remained.

## Follow-up polish

- P3: The generated source uses softer antialiasing and slightly larger outer
  margins. The implementation retains Local Note's established 2× native
  rendering and 24-point settings inset.

## Implementation checklist

- [x] Match selected gallery-first visual direction.
- [x] Preserve fixed popover and footer behavior.
- [x] Verify default, dark settings, dark outline, and light calendar states.
- [x] Verify appearance persistence, fallback, contrast, and regression tests.

final result: passed
