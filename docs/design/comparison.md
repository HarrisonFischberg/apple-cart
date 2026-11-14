# Design comparison (Phase 3B)

Status: awaiting the owner's pick, 2026-11-14. Written by Sonnet from the rendered screenshots; Opus has not reviewed it (the workflow gives the recommendation to Opus; the owner can ask for that pass).

Screenshots: `docs/design/screenshots/`, macOS 26, 2x, light and dark, mock desktop with menu bar. Tool: the `Shots` executable in each concept (SwiftUI through an NSWindow), not the browser preview. All three use the same demo data and show the same state: charging paused because the battery is 41.2 °C against a 40 °C limit. Branches: `ui-1`, `ui-2`, `ui-3` in worktrees `../apple-cart-ui-N`, local only.

| | C1 Tape | C2 Rams | C3 Course |
| --- | --- | --- | --- |
| World | hardware-store tape measure | Braun / Rams product sheet | orienteering map and legend |
| Signature | limit is a tape-measure lock tab sliding on a scale; charge is the yellow blade | limit is a round dial with one orange pointer | 24 h history as a map; limit line and numbered controls are the plan |
| Navigation | yellow top tab strip | left icon rail | bottom icon bar |
| Panel (pt) | 360 x 830 / 880 | 460 x 600 | 400 x 680 |
| Palette | safety yellow, black, ash; red for heat | cool gray and ink; one orange for the pointer, the active tab and the pause | white, brown contour hairlines, blue power, olive caution, purple plan |
| Type | DIN Condensed numerals + system | Helvetica Neue, two weights | Avenir Next Condensed numerals + system |
| Reads first | charge and limit on the tape | the dial | the history map and the reason |
| Shows the reason | red callout under the tape | orange text under the dial | olive callout, with the numbered event that caused it |

## What each does well, and where it is weak

**C1 Tape.** The most ownable of the three, and the best single interaction (drag the lock tab, live readout, detents). Yellow means "active" everywhere and that rule reads instantly. Weak: at 830 pt it is far too tall for a menu bar panel (a real one scrolls, so the first 600 pt are what people see: tape, reason, buttons, power); the full yellow header strip is loud for a tool opened many times a day; the white switch knob on yellow is low contrast in light mode.

**C2 Rams.** The quietest and the most "part of macOS" (principle 4). Smallest panel (600 pt, no scrolling), clean grid, the dial is a good limit control, and orange appears only where something is active or paused. Weak: least distinctive; the white label on the orange active tab is about 3:1 (fails 4.5:1 and needs a darker orange or dark text); the switch "on" state in dark mode is a weak gray. The dial is wide, so the panel is 460 pt.

**C3 Course.** The most informative. It is the only one that answers "why is it at 74% and not 80%?" with a history and numbered events, and it puts the schedule on the same legend. Fits at 680 pt with the best chart (axes, plugged-in spans, heat-pause band). Weak: the notation is a learning cost; it is the densest panel; the bottom tab bar is the least Mac-like of the three; the purple is reserved for the plan only, which has to be held as the app grows.

## Things all three need before they ship (Phase 3C)

- Replace the drawn switch and sliders with native controls plus tint; check focus rings, VoiceOver and arrow-key handling (built but not exercised in any concept; no concept has been run interactively, only rendered).
- The Network chart's top label (8 MB/s) was invented by builders because the demo data is normalized; real data must set the axis.
- Clean and Clipboard & Tools tabs are empty placeholders in every concept.
- Fonts are system fonts for the previews. DIN Condensed and Avenir Next Condensed ship with macOS but their redistribution terms must be checked before the app bundles them.
- C1 and C2 each have a measured contrast problem above; C3's contrast was judged by eye only.

## Recommendation (Sonnet's, not yet reviewed by Opus)

**C2 Rams as the base**, then borrow C3's numbered event legend for the history chart later. It best matches the product principle that the app should feel like part of macOS, it is the only one that fits a menu bar panel without scrolling, and its weaknesses (orange contrast, dark-mode switch) are small fixes. Choose C3 instead if the point of the app to you is understanding battery behavior at a glance; choose C1 if you want the app to look unmistakably its own and accept a taller, louder panel.

Mixing is allowed: for example "C2's shell with C1's tape slider" is a valid pick.
