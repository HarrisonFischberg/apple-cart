# Design system record (Phase 3C)

Approved direction: C4 Tiles (owner, 2026-11-14). Source of truth: `DESIGN.md` (tokens, 8 sections) and `.impeccable/design.json` (sidecar). Concept code: `design/concepts/c4`. Screenshots: `docs/design/screenshots/c4-*.png`.

Documented: 13 color roles with light and dark values, 11 type styles, 11 components with tokens, 8 in the sidecar. Written by the shipped `impeccable-documenter` from the built SwiftUI source.

## Impeccable commands, honestly

Ran this session: `context`, `init` (PRODUCT.md), `concept-seed` (direction roll, for C1-C3), the documenter agent (DESIGN.md and sidecar).
Not run: `critique`, `audit`, `extract`, `polish`. They need a browser preview or HTML/CSS and have no verdict on native Swift code (platform profile: NOT APPLICABLE for native-only targets). Their lean-mode role is replaced by Phase 4's per-milestone review and Phase 5's accessibility checks on the running app. The detector was not run for the same reason.

## Gaps and decisions to carry into Phase 4

- **Limit range:** the concept clamps the limit to 50-100; the product range is 20-100 (blueprint, policy engine). Build to 20-100. The Limit tile's bar is about 40 pt wide, a small drag target; widen it or move the drag to the Charge tile.
- **Hex values for borders and tracks** in `DESIGN.md` are approximations of `Color.primary` at 8% and 12%, not read from pixels. Contrast ratios cite hand checks in `Tokens.swift` (secondary at least 6:1, accents at least 5.4:1); recompute from rendered output in Phase 5.
- **Stand-ins in the preview, to replace in production:** drawn switch (use native `Toggle` with tint), solid panel (a material is allowed), system fonts (SF only for the shipping build, so no font license row is needed).
- **Focus ring:** the concept draws none; use the system default and verify keyboard order in Phase 5.
- **Panel height:** Battery is about 936 pt and System runs past 680; both scroll. The System preview cut off the quick-toggles tile; check it in the running app.
- **Not exercised in any concept:** dragging, arrow keys, the open overflow menu, VoiceOver.
- **Other concepts:** C1-C3 stay on local branches `ui-1`, `ui-2`, `ui-3` (not pushed). Ideas worth revisiting: C3's numbered event legend for the history tile, C1's tape-style limit slider.
