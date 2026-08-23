# Design QA: checkbox parent with numbered children

- Source visual truth: `/var/folders/sp/dx4qcrpj2xg3v2jf6b8yglv80000gn/T/codex-clipboard-ab9f228e-5aec-4e14-be08-d6b4a46a1d7b.png`
- Implementation screenshot: `/Users/bozhang/Documents/ChatGPT/app-local-note/build/outline-hierarchy-preview.png`
- Combined comparison: `/Users/bozhang/Documents/ChatGPT/app-local-note/build/hierarchy-comparison.png`
- State: light appearance; checkbox parent rows with numeric depth-1 children and an alphabetic depth-2 child; completed text shown with strikethrough.
- Viewport: native macOS popover content at 440 × 560 points, captured at 2× as 880 × 1120 pixels.
- Source dimensions: 1502 × 1390 pixels. The focused comparison uses a 930 × 1120 source crop normalized to an 880 × 1120 panel.
- Implementation dimensions: 880 × 1120 pixels, equivalent to 440 × 560 points at 2× density.

## Full-view comparison evidence

The source and implementation share the target information hierarchy: top-level checkbox rows, indented `1. / 2. / 3.` children, a further-indented `a.` child, continued numeric numbering after the alphabetic subtree, and text-bounded strikethrough. The implementation intentionally retains Local Note's compact 440-point native popover, system background, header, and footer instead of copying the wider Notion-like canvas.

## Focused region comparison evidence

The combined comparison checks the `线上工单`, `客诉专项`, and `数据统计` regions at readable scale. Checkbox alignment, numeric indentation, alphabetic second-level indentation, sequence continuation, and strikethrough extent match the requested structure. A separate focused crop was unnecessary because these details are legible in the combined evidence.

## Required fidelity surfaces

- Fonts and typography: system Chinese font and optical weights remain native to the existing app. Parent items are visually stronger than completed child items; numbering and alphabetic markers are aligned consistently. The larger source typography is an expected difference from the compact popover.
- Spacing and layout rhythm: parent rows, depth-1 numeric rows, and depth-2 alphabetic rows have distinct 18-point indentation steps and consistent vertical rhythm. The source's wide document margins are intentionally not reproduced.
- Colors and visual tokens: the app retains native light-mode background, primary text, secondary completed text, and system checkbox tokens. Contrast remains readable.
- Image quality and asset fidelity: the reference contains no raster imagery, logos, or custom illustration assets. Native controls remain sharp at 2× density.
- Copy and content: representative source content was used to verify wrapping, numbering, alphabetic nesting, and completed states.

## Interaction verification

- Return after a parent creates and focuses a peer row.
- Tab on that empty checkbox converts it into the first depth-1 numbered child.
- Return continues numeric children.
- Tab on a numbered child creates the depth-2 alphabetic structure.
- Shift-Tab returns from alphabetic depth to the next numeric item.
- Backspace on an empty numeric child converts and outdents it to the next top-level checkbox.
- All interactions were dispatched through the real AppKit field editor in the automated UI suite.
- Browser console checks are not applicable to this native AppKit/SwiftUI application.

## Comparison history

1. First pass: P2 — strikethrough extended across the unused width of the text field, unlike the source where it ended with the text. Fixed by applying native attributed-string strikethrough to the text range instead of drawing a full-width overlay.
2. Second pass: text-bounded strikethrough and the full checkbox → numeric → alphabetic hierarchy matched the focused source evidence. No actionable P0/P1/P2 differences remained.

## Findings

No actionable P0/P1/P2 findings remain for the requested hierarchy and interaction behavior.

## Follow-up polish

- P3: The reference uses a wider document canvas and larger type. Local Note intentionally keeps its existing compact native popover dimensions and system typography.

final result: passed
