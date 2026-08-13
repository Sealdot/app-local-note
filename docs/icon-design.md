# App icon design

## Selected direction

The production icon uses the **folded checklist** direction: one self-contained
paper note, a folded corner, and two checked rows. It maps directly to Local
Note's daily work-log behavior while remaining readable at 16–32 points.

The restrained lake-blue and mint accents distinguish the application icon
without making the menu-bar utility feel heavy. The status bar intentionally
continues to use the system `checklist` template symbol so macOS can adapt it
automatically for light, dark, active, and inactive menu bars.

## Files

- `Resources/Brand/AppIcon-1024.png`: canonical 1024 px source artwork
- `Resources/AppIcon.icns`: deterministic macOS icon family used by packaging
- `scripts/generate-icon.sh`: regenerates all required icon sizes and `.icns`

The generated `.iconset` directory is ignored because it is derived from the
canonical source.

## Generation provenance

- Workflow: Creative Production logo exploration
- Generation route: built-in ImageGen
- Selected from four directions: folded checklist, calendar card, check path,
  and minimal note
- Selection criteria: small-size legibility, fit with daily nested checklists,
  distinct silhouette, and compatibility with a lightweight native utility

Final prompt:

```text
Use case: logo-brand
Asset type: 1024×1024 macOS app icon for the lightweight “Local Note” menu-bar utility
Primary request: Create one original, production-polished macOS app icon concept centered on a single slightly folded-corner paper note with exactly two clearly readable checked checklist boxes. The symbol should immediately communicate local-first offline notes, lightweight daily task tracking, and calm productivity.
Scene/backdrop: a clean macOS squircle app-icon composition filling the square canvas, with a warm milk-white / ivory background; no external scene.
Subject: one centered compact sticky-note sheet with a subtle top-right folded corner; two distinct square checkboxes with clean check marks and two short understated list strokes. Suggest “local/offline” through quiet self-contained solidity and compactness only—do not add cloud, Wi-Fi, download, computer, device, lock, or sync symbols.
Style/medium: refined flat vector-like icon, simple geometric construction, strong silhouette, crisp edges, friendly but professional, optimized to remain recognizable at 16–32 px menu-bar/app-launcher sizes.
Composition/framing: single centered mark; generous even breathing room; balanced macOS squircle proportions; frontal view with only a tiny dimensional lift; avoid tiny details.
Color palette: warm milk-white background, deep graphite linework, restrained lake-blue and mint-green accents only. Use lake-blue for one checkbox/check and mint-green for the other or the folded-corner accent. High enough contrast for small sizes.
Materials/textures: mostly matte flat color; at most a very subtle paper feel; no grain.
Lighting/mood: calm, focused, lightweight, local, trustworthy; virtually flat lighting.
Text: none.
Constraints: exactly one icon, square 1024×1024 composition; exactly one folded-corner note and exactly two clear check marks; no letters, no words, no numbers, no watermark; no Notion logo or copied brand mark; no complex shadow, no dramatic 3D, no photorealism, no transparency, no mockup frame, no extra floating objects.
Avoid: busy background, heavy gradients, glassmorphism, neon, gloss, bevels, excessive depth, multiple notes, three or more checks, cloud or network imagery, browser imagery, device imagery, logo text.
```

