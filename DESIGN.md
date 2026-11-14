---
name: Apple Cart (working title)
description: A menu bar panel where everything is a tile: a launcher of tools, and each tool a dashboard of rounded stat tiles.
colors:
  ground-light: "#F1F1F4"
  ground-dark: "#0B0B0D"
  tile-light: "#FFFFFF"
  tile-dark: "#18181B"
  border-light: "#00000014"
  border-dark: "#FFFFFF14"
  text-light: "#111114"
  text-dark: "#FFFFFF"
  secondary-light: "#5B5B66"
  secondary-dark: "#A1A1AA"
  track-light: "#0000001F"
  track-dark: "#FFFFFF1F"
  blue-light: "#0A5ED7"
  blue-dark: "#5AB0FF"
  on-blue-light: "#FFFFFF"
  on-blue-dark: "#0B0B0D"
  amber-light: "#8A5300"
  amber-dark: "#F5A524"
  amber-fill-light: "#FFF1D6"
  amber-fill-dark: "#2B2008"
  amber-text-light: "#5C3600"
  amber-text-dark: "#FFD58A"
  amber-bar-light: "#C77700"
  amber-bar-dark: "#F5A524"
  green-light: "#177A3C"
  green-dark: "#4ADE80"
typography:
  value:
    fontFamily: "SF Pro (system)"
    fontSize: "24px"
    fontWeight: 600
    fontFeature: "tabular-nums"
  unit:
    fontFamily: "SF Pro (system)"
    fontSize: "12px"
    fontWeight: 500
    fontFeature: "tabular-nums"
  header-title:
    fontFamily: "SF Pro (system)"
    fontSize: "17px"
    fontWeight: 600
  search-field:
    fontFamily: "SF Pro (system)"
    fontSize: "15px"
    fontWeight: 400
  state-title:
    fontFamily: "SF Pro (system)"
    fontSize: "15px"
    fontWeight: 600
  row:
    fontFamily: "SF Pro (system)"
    fontSize: "13px"
    fontWeight: 400
    fontFeature: "tabular-nums"
  tile-title:
    fontFamily: "SF Pro (system)"
    fontSize: "12px"
    fontWeight: 500
  body-small:
    fontFamily: "SF Pro (system)"
    fontSize: "12px"
    fontWeight: 400
  label:
    fontFamily: "SF Pro (system)"
    fontSize: "11px"
    fontWeight: 500
  button-label:
    fontFamily: "SF Pro (system)"
    fontSize: "11px"
    fontWeight: 600
  caption:
    fontFamily: "SF Pro (system)"
    fontSize: "11px"
    fontWeight: 400
rounded:
  chip: "999px"
  button: "8px"
  tile: "16px"
  panel-preview: "14px"
spacing:
  tile-pad-x: "10px"
  tile-pad-y: "12px"
  gap: "12px"
  panel-pad: "14px"
  header-height: "52px"
  panel-width: "420px"
  column: "122.67px"
  control-height: "28px"
components:
  tile:
    backgroundColor: "{colors.tile-dark}"
    textColor: "{colors.secondary-dark}"
    typography: "{typography.tile-title}"
    rounded: "{rounded.tile}"
    padding: "12px 10px"
    width: "122.67px"
  tile-amber:
    backgroundColor: "{colors.amber-fill-dark}"
    textColor: "{colors.amber-text-dark}"
    rounded: "{rounded.tile}"
    padding: "12px 10px"
  tile-off:
    backgroundColor: "#00000000"
    textColor: "{colors.secondary-dark}"
    rounded: "{rounded.tile}"
  launcher-tile:
    backgroundColor: "{colors.tile-dark}"
    textColor: "{colors.text-dark}"
    typography: "{typography.label}"
    rounded: "{rounded.tile}"
    padding: "8px"
    height: "104px"
    width: "89px"
  header-button:
    textColor: "{colors.text-dark}"
    size: "28px"
  chip:
    backgroundColor: "#00000000"
    textColor: "{colors.text-dark}"
    typography: "{typography.label}"
    rounded: "{rounded.chip}"
    height: "28px"
    padding: "0 9px"
  chip-selected:
    backgroundColor: "{colors.blue-dark}"
    textColor: "{colors.on-blue-dark}"
    rounded: "{rounded.chip}"
    height: "28px"
  small-button:
    backgroundColor: "#00000000"
    textColor: "{colors.text-dark}"
    typography: "{typography.button-label}"
    rounded: "{rounded.button}"
    height: "28px"
  small-button-filled:
    backgroundColor: "{colors.blue-dark}"
    textColor: "{colors.on-blue-dark}"
    typography: "{typography.button-label}"
    rounded: "{rounded.button}"
    height: "28px"
  progress-bar:
    backgroundColor: "{colors.track-dark}"
    height: "4px"
  switch-standin:
    backgroundColor: "{colors.blue-dark}"
    rounded: "{rounded.chip}"
    width: "38px"
    height: "22px"
---

# Design System: Apple Cart (working title)

Documented from the built concept in `design/concepts/c4/` (Tokens.swift, Header, LauncherView, BatteryView, SystemView, PanelView) and `design/concepts/shared/.../Controls.swift`, checked against `docs/design/screenshots/c4-*.png`. Every color has a light and a dark value, defined together. In the frontmatter, `-light` and `-dark` suffixes are the two appearances of one role; component entries show the dark value only, light is the same role with its `-light` counterpart. "Apple Cart" is a working title, not the public name.

## Overview

**Creative North Star: "The Tile Shelf"**

One panel, one pattern: everything is a tile. Home is a grid of the tools the user switched on; a tool opens into a dashboard of tiles; the limit, the reason, and the history are tiles like any other. The panel is quiet and monochrome, and color appears only when it carries a meaning: amber for paused or caution, blue for the user's control (limit, selection, switches), green for healthy.

It is dark-first but designed twice: the light appearance is its own set of values (white tiles on a cool light-gray ground), not an inversion. Density is a glance panel: one big number per tile, a short caption, a thin bar. Native macOS behavior (menus, steppers, keyboard) stays native; the world lends only palette, type, density, and the tile.

**Key Characteristics:**
- A single container, the tile (16 pt continuous corner, 1 pt hairline), builds every view.
- Near-black ground with slightly lifted tiles in dark; white tiles on pale gray in light.
- Three accents, each with one meaning; everything else is neutral.
- System font only; values at 24 pt semibold with tabular digits, everything else 11 to 17 pt.
- Flat: no shadows on any tile or control; depth is tonal (ground, then tile) plus hairline.

## Colors

A monochrome ground-and-tile pair with three meaning-bound accents.

### Primary
- **Control Blue** (light #0A5ED7 / dark #5AB0FF): the user's control. Limit bar fill, selected chip, filled button, switch on-state, history limit line and plugged-in bands (at 16-30% opacity).
- **On Blue** (light #FFFFFF / dark #0B0B0D): text on a Control Blue fill.

### Secondary
- **Caution Amber** (light #8A5300 / dark #F5A524): a value that is over its limit or a paused state: tile icon, temperature value, the heat caption, the tile outline (at 70%).
- **Amber Fill** (light #FFF1D6 / dark #2B2008): the background of an amber tile.
- **Amber Text** (light #5C3600 / dark #FFD58A): text inside an amber tile.
- **Amber Bar** (light #C77700 / dark #F5A524): the progress bar fill for a caution value.

### Tertiary
- **Healthy Green** (light #177A3C / dark #4ADE80): good state only: the health label and the fan-speed bar.

### Neutral
- **Ground** (light #F1F1F4 / dark #0B0B0D): the panel background.
- **Tile** (light #FFFFFF / dark #18181B): tile and launcher-tile surface.
- **Hairline** (primary at 8%: about #00000014 light, #FFFFFF14 dark): 1 pt tile outline. Controls use it at double strength (16%).
- **Ink** (light #111114 / dark #FFFFFF): values, headings, control labels.
- **Secondary Ink** (light #5B5B66 / dark #A1A1AA): tile titles, captions, axis labels, off tools. Source comment states at least 6:1 on tile.
- **Track** (primary at 12%): bar track, chart gridlines, off-state of switches (18%).

### Named Rules
**The One Meaning Rule.** Each accent means one thing: amber is paused or over a limit, blue is the user's control, green is healthy. Never use an accent as decoration.
**The Paired Appearance Rule.** Every color role has an explicit light and dark value. Do not derive one by inverting the other.
**The Tinted Text Rule.** Accent text on a tile uses the accent's own text value (Caution Amber, Amber Text), which was hand-checked to at least 5.4:1 in both appearances. Do not put a bar-fill value on text.

## Typography

**Display Font:** SF Pro (system), `Font.system`
**Body Font:** SF Pro (system)
**Label/Mono Font:** none; tabular digits via `monospacedDigit()`

**Character:** One family at small sizes, with weight and tabular digits carrying hierarchy. Numbers are the headline of every tile.

### Hierarchy
- **Value** (600, 24 pt): the one large number per tile; unit beside it is 12 pt medium, baseline-aligned, 2 pt apart.
- **Header title** (600, 17 pt): current view name in the panel header. Search field text is 15 pt regular.
- **State title** (600, 15 pt): the headline of the state tile, in Amber Text; its reason line is 12 pt regular.
- **Row** (13 pt, medium for primary text, regular for time/values): schedule and quick-toggle rows.
- **Tile title** (500, 12 pt): the label next to the tile icon, in Secondary Ink. Body-small is 12 pt regular for explanatory sentences.
- **Label** (500, 11 pt): launcher tool names, chip text, "Off" mark. Button label is 11 pt semibold.
- **Caption** (400, 11 pt): units, shortcut hints, axis labels, helper text, in Secondary Ink.

### Named Rules
**The Tabular Rule.** Any number that can change while the panel is open uses tabular digits so the layout does not jitter.
**The Small Ceiling Rule.** Nothing but the header title and values is above 15 pt; the panel is not a place for display type.

## Layout

A fixed 420 pt panel hanging from the status item. Content inset 14 pt (392 pt inner). Tiles sit on a three-column grid: one column is 122.67 pt, two columns 257.33 pt, three 392 pt, with 12 pt gaps horizontally and vertically. Rows have fixed heights chosen to the content (Battery: 124, 152, 148, 160, 164; System: 120, 148, 128, 84, 168, 200). The header is 52 pt tall with 10 pt side inset: back arrow (tool views only), title or search field, search button, overflow menu. Home is a 4-column launcher grid of 104 pt tiles (89 pt wide), five rows, plus an "Add tools" tile. Tool views scroll when taller than about 640 pt (shot height caps at 680). Tile inner padding is 10 pt horizontal, 12 pt vertical, 8 pt between icon row and content. Interactive hit areas are at least 28 pt.

Narrow and wide tiles alternate within a row to keep the rhythm; a row always totals three columns.

## Elevation & Depth

Flat. Tiles carry no shadow at rest or in any state. Depth is tonal: the tile is one step lighter than the ground in dark and white on gray in light, with a 1 pt hairline. A switched-off tool or tile drops its fill and uses a dashed hairline (4 on, 3 off) instead of shadow. Shadows exist only in the preview harness (panel drop shadow, radius 22) and on the thumb of the stand-in switch; neither is part of the system.

### Named Rules
**The Flat Tile Rule.** Tiles never get shadows. State is shown by fill, outline color, or dash, not by lift.

## Shapes

Soft continuous rounded rectangles. Tiles and launcher tiles: 16 pt. Buttons: 8 pt. Chips, pills, bars, steppers, and the header "Add task" pill: full capsule or circle. Bars are 4 pt capsules with a 2 x 10 pt marker notch for a limit. Outlines are 1 pt, always inside the shape (`strokeBorder`). Icons are SF Symbols at 12 pt (tile title), 14 pt (header), 18 pt (launcher), medium weight.

## Components

### Tile
The universal container. Icon + title row (12 pt, Secondary Ink), optional trailing element, then content. Normal: Tile fill, hairline. **Amber**: Amber Fill, amber outline at 70%, icon in Caution Amber, title in Amber Text. **Off**: transparent fill, dashed hairline. Always one value, at most three short captions.

### Launcher Tile
104 x 89 pt, 8 pt padding: 18 pt icon top-left, name (11 pt medium, two lines max, bottom-aligned), shortcut hint below (11 pt, Secondary Ink). Off tools show an outlined "Off" pill and Secondary Ink text on a dashed outline. Combined into one accessibility element with name, shortcut and off state.

### Header
52 pt. Back chevron only in tool views. Title swaps for a plain search field when searching. 28 x 28 pt borderless icon buttons; overflow is a native menu (Keep open, Settings..., Collapse).

### Progress Bar
4 pt capsule on Track, fill in Control Blue (Amber Bar for caution, Green for healthy), optional 2 x 10 pt Ink notch for a limit. Hidden from accessibility; the tile carries the label.

### Limit Control
A tile with value, a bar you can drag (detents every 5, range 50 to 100 in the build), and circular minus/plus steppers (22 pt circle in a 28 pt target). Left/right arrows adjust by 5; VoiceOver adjustable.

### Chip and Small Button
Chip: 28 pt tall capsule, 11 pt medium, outlined; selected fills Control Blue with On Blue text. Small button: 28 pt tall, 8 pt radius, 11 pt semibold; filled = Control Blue, plain = outline.

### Switch
Concept: `PreviewSwitchStyle`, a drawn 38 x 22 capsule with Control Blue on-track and a white thumb. It is a screenshot stand-in only. Production intent: native `Toggle` with `.tint(Control Blue)`, same footprint.

### Charts
Canvas line charts: Ink 1.75 pt history line, Track gridlines, Control Blue dashed limit line (1.5 pt, 4/3), plugged-in bands at 16% blue, axis labels 11 pt Secondary Ink tabular.

## Do's and Don'ts

### Do:
- **Do** build every new view from `Tile`, in whole columns (1, 2, or 3) with a 12 pt gap.
- **Do** give every new color a light and a dark value and check text at 4.5:1 or better on its tile.
- **Do** use native SF Symbols, native menus, and native keyboard behavior.
- **Do** honor Reduce Motion: the limit change animates with a 0.2 s spring, and snaps when Reduce Motion is on.
- **Do** give each tile an accessibility label that states the value and its context, and hide decorative bars and charts from VoiceOver.
- **Do** use the production switch: native `Toggle` with tint. The drawn `PreviewSwitchStyle` is a harness stand-in (offscreen windows render native switches gray).

### Don't:
- **Don't** add shadows, gradients, or glow to tiles or controls.
- **Don't** use an accent for decoration, or add a fourth accent.
- **Don't** use a big ring with a percentage, three identical stat cards, or sparklines that replace readable data.
- **Don't** use a non-system font for UI; if a licensed or custom face is considered for previews or branding later, run a font licensing check first. The build uses system fonts everywhere.
- **Don't** assume a vibrancy material: the panel is a solid Ground fill (`fillPanel`). A material is an optional production decision, to be tested against the 4.5:1 contrast targets, not a recorded rule.
- **Don't** copy another app's name, icons, or copy; the working title "Apple Cart" must not ship as a public name.
