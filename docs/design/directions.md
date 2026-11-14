# Design directions (Phase 3B)

Status: C4 Tiles approved by the owner 2026-11-14 (C1-C3 not chosen). DESIGN.md follows in Phase 3C.

Mode: Operate. Platform: native macOS menu bar panel (SwiftUI + AppKit). The core screen is S02 (Battery tab), with S03 (System tab) to show the tab pattern holds. Seed: `seed:a6ed928998647bf4` (Impeccable concept-seed, direction scope, operate mode).

## Brief (shape, confirmed by assumption)

- **Job and audience:** Mac power users open the panel in short moments while doing other work. They glance to learn the battery's state and why, adjust the charge limit, and leave. Used often, usually one-handed on a trackpad, in everything from a dim room to daylight, so both appearances must be first-class.
- **Outcome:** within two seconds they can read charge, limit, and the reason charging is or isn't happening; changing the limit is one drag; Top up is one click.
- **Real content and ranges:** one set of demo data for all concepts (`design/concepts/shared`). The demo state is the interesting one: charging is paused because the battery is 41.2 °C against a 40 °C heat limit. Ranges: charge 5-100%, limit 20-100%, temperature 20-45 °C, 0-3 schedule items, 24 h of history.
- **States that matter:** heat pause (shown), charging, holding at limit, on battery, helper missing, calibration, tool switched off (empty state with a next action), permission needed.
- **Untouched:** purpose and function of every tool (`replica/features.csv`); tabs Battery, System, Clean, Clipboard & Tools; native controls and keyboard behavior.
- **Anti-goals:** a big ring with a percentage and three stat cards; sparklines standing in for data; decoration that hides state; copying another app's identity.
- **Assumptions I made instead of interviewing** (the pick below is the confirmation): the owner is the first user and prefers native macOS feel in light and dark; panel width 340-480 pt; no brand assets exist yet; public name undecided, so no name appears in the designs except as a placeholder.

## How the three worlds were chosen

Seven grounded worlds from the audience's graphic and physical culture, ordered by resonance: (1) Braun and Rams product sheets, (2) Swiss railway timetable and station clock, (3) the nutrition-facts label, (4) the hardware-store tape measure, (5) the weather-service isobar chart, (6) pharmacy blister pack and leaflet, (7) the houseplant care card. The roll assigned #4. My top-ranked candidate is #1 and is presented as the pick. Of the five catalog challengers, one is competitive and four are declined.

In Operate mode a world lends only type, palette, density, and one signature move. Layout, navigation, and controls stay native.

| Card | Source | Verdict |
| --- | --- | --- |
| C1 Tape | assigned, grounded #4 | built |
| C2 Rams | Impeccable's pick, grounded #1 | built; honest risk: familiar, it is where most Mac utility designs land |
| C3 Course | catalog `notation-diagram-systems-orienteering-map` | competitive: holds product clarity (schedule as numbered controls, history as terrain), weaker on audience identification |
| (not built) | `variable-font-specimen` | declined; kept: a live coordinate readout while dragging, and reduced motion snaps between named detents. Raised into C1. |
| (not built) | `design-annual-s-plate-section` | declined; near-duplicate of C2's Swiss print family; kept: one voice for display and caption on a strict 1 px hairline grid. Raised into C2. |
| (not built) | `aww2-zoo-gardens-guide-map` | declined; kept: a committed flat colour field means a state, never decoration. Raised into C1 (yellow means active). |
| (not built) | `vernacular-ephemera-cassette-j-card`, `pop-culture-shelf-doujin-event-catalog` | declined; kept: running times right-aligned at the margin. Raised into C3. |

## C1 Tape (assigned)

Personality: practical, tactile, quick to read. For the person who wants a tool, not a toy.

- THESIS: Battery care is a measured quantity, so the limit control is a tape measure. Charge is the extended yellow blade; the limit is the black lock tab you slide to a mark. Refuses the big-ring-plus-percentage panel.
- OWN-WORLD: Safety yellow `#FFC800` for the shell strip and blade, black ink, ash-white ground; red only for heat and critical; DIN Condensed Bold numerals with system text for labels; 1 px ticks, long every 5, numerals every 10. Dark: charcoal ground, yellow unchanged. Yellow always means active or live.
- STORY: Glance: charge, limit, and the reason. Slide the lock tab to change the limit, with a live numeric readout and detents at 20, 50, 80, 100. Top up is one button.
- FIRST VIEWPORT: Yellow header strip with the four tabs. Below it the tape spans the full panel width with the blade at 74 and the lock at 80; the state line and the plain-language reason sit directly under the tape. Then Top up, power flow as three numbers, details, schedule.
- FORM: grounded candidate 4 of 7, `seed:a6ed928998647bf4`.
- Organisation: top tab strip, one column, 360 pt wide.
- FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.

## C2 Rams (pick)

Personality: calm, quiet, nothing shouts. For the person who wants it to feel like part of the Mac.

- THESIS: Colour is spent only on what is active. The limit is a round dial with a printed scale and one orange pointer; everything else is alignment and silence. Refuses decorative colour.
- OWN-WORLD: Cool grays (light `#E4E6E5`, dark ET-calculator black `#161717`), ink, and one orange `#F26A1B` on the dial pointer, the active rail item, and the pause state. Helvetica Neue in two weights, 1 px hairlines, small radius (6), one baseline grid with display and caption in the same face.
- STORY: Read the dial first (charge arc, limit pointer), then the four readings beside it, then the reason line. Turn the dial or use the arrow keys to move the limit.
- FIRST VIEWPORT: Left icon rail (four tabs, settings below). Main area: dial at left with the charge arc and orange pointer at the limit; to its right a stacked column of readings (charge, hardware percentage, temperature, power); under both, the state line and reason; then grouped native-style list rows for Top up, Discharge, Heat protection.
- FORM: grounded candidate 1 of 7 (Impeccable's pick), `seed:a6ed928998647bf4`.
- Organisation: left icon rail, two-column main area, 460 pt wide.
- FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.

## C3 Course (challenger, competitive)

Personality: precise, map-like, for people who like to read the data.

- THESIS: The last 24 hours are terrain and your battery plan rides over it as a purple course. Charge history is the map; the limit is the course line; events and scheduled tasks are numbered controls; a legend table explains every mark. Refuses ring-plus-sparkline.
- OWN-WORLD: White ground with brown contour hairlines under the chart only; blue for power flow, olive for caution, yellow for highlights, course purple `#B5238C` reserved for the plan (limit line, controls, schedule). Avenir Next Condensed numerals with system text. Dark: night-forest ground `#131A16` with the same inks, softened. Legend rows set like an orienteering description sheet: numbered cell, symbol cell, text, time right-aligned.
- STORY: Read the map: where charge has been, where the limit sits, what happened at each numbered control, what comes next. Drag the purple limit line to change it.
- FIRST VIEWPORT: Chart first, full width, 24 h with plugged-in spans shaded, the limit as a dashed purple line, five numbered controls on the curve. Beneath it the Now row (state, reason), then the legend table listing controls 1-5 and the three scheduled tasks as controls 6-8. Tabs run along the bottom as a native-style icon bar.
- FORM: catalog challenger `notation-diagram-systems-orienteering-map`, `seed:a6ed928998647bf4`.
- Organisation: bottom icon tab bar, map-first vertical stack, 400 pt wide.
- FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.

## Build notes for all concepts

- Fonts are macOS system fonts only for the previews (SF, Helvetica Neue, DIN Condensed Bold, Avenir Next Condensed). A shipping font needs a license row in `docs/asset-licenses.md`.
- Previews use a drawn switch (`PreviewSwitchStyle`) and drawn sliders because an offscreen window is never active and native controls render gray in screenshots. Production uses native controls with the concept's tint.
- The panel background is solid (no live vibrancy) so screenshots are deterministic. Production may use a material.
- Native macOS has no sparklines requirement; every chart in the concepts carries axis labels and values.
- Screenshots: macOS 26, `NSHostingView` rendered through an `NSWindow` at 2x, light and dark, on a mock desktop with menu bar. Tool: the `Shots` executable in each concept (not the browser preview, not Playwright).

## C4 Tiles (owner-pinned: "very closely mimic the reference's display")

Added 2026-11-14 after the owner saw C1-C3 and asked for the panel to closely follow the reference app's display (Source A, vorssaint.com). A user-pinned direction beats the roll, so it did not go through concept-seed.

What was observed on the reference's public live demo (public page, read only; nothing downloaded):
- A dark, rounded panel under the notch with the current view's title top-left and a "..." menu top-right (Keep open, Settings, Collapse).
- Home view is a launcher: a grid of tool tiles (icon above label, a keyboard-shortcut hint under the label), with a back arrow and a search icon in the header and pager dots at the side.
- A tool view is a dashboard of rounded tiles: small icon + label top-left, one large value, a thin progress bar; narrow tiles three across, wider tiles two across, mixed row heights.
- A few round buttons float beside the panel (grid, timer, settings, volume).

What this concept takes: the structure and interaction model (launcher grid with shortcut hints and search, header with title and overflow menu, tool views as stat tiles, wide and narrow tile rhythm, pager). What it does not take: the reference's name, logo, icons, copy, imagery, or the notch-island placement (not one of the owner's picks). Icons are SF Symbols, copy is original, the panel hangs from the status item. Impact on the plan: this replaces the four-tab IA (S02-S05) with a launcher plus one tile view per tool; if approved, `replica/recon.md`, `docs/blueprint.md` and `prd.md` are updated in Phase 3C.

- THESIS: One panel, one pattern: everything is a tile. Home is a grid of the tools you switched on; a tool opens into a tile dashboard; the limit, the reason and the history are tiles like any other.
- OWN-WORLD: Dark first: near-black ground `#0B0B0D`, tiles `#18181B` with a 1 px `#FFFFFF14` border, 16 pt radius, 12 pt gaps, white text, secondary `#A1A1AA` (must stay >= 4.5:1). Light appearance designed separately: ground `#F1F1F4`, white tiles, hairline `#00000014`. SF Pro (system), values 24 pt semibold with tabular digits, labels 11-12 pt. One accent per meaning: amber `#F5A524` for paused or caution, system blue for the limit, green for healthy; everything else is monochrome.
- STORY: Open, see your tools, open one, read its tiles, act. For battery: the state tile says why, the limit tile changes the limit, Top up is a tile you click.
- FIRST VIEWPORT (Battery view, 420 pt wide): header (back arrow, "Battery", search, "..." menu). Row 1: Charge tile (74%, thin bar with a notch at the 80% limit), Limit tile (80%, minus and plus steppers and drag on the bar), Temperature tile (41.2 C against 40 C, amber). Row 2: a wide State tile (paused, with the plain-language reason) beside a Top up action tile. Row 3: Power tile (to Mac, to battery, adapter rating), Health tile (cycles, maximum capacity), Hardware percentage tile. Row 4: a wide History tile (24 h chart with plugged-in spans and the limit line, axes labelled). Row 5: Schedule tile (three items).
- ALSO RENDER: Home launcher (grid of tool tiles with shortcut hints, search in the header, pager dots, one tile shown as switched off with an "off" mark) and the System view (CPU, GPU, Memory tiles; Network, Disk, Power tiles; Keep awake tile; Fan safe mode tile in its off state; SoC temperature).
- FORM: owner-pinned, no seed.
- Organisation: launcher home, tool views reached by tile, back arrow, search, 420 pt wide, scrolls beyond about 640 pt.
- FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.
