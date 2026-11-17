# Battery feature parity plan

Written 2026-11-15 from the public feature page of a reference battery app (AlDente, apphousekitchen.com/aldente-overview/features/).
Clean-room rule: we match what each feature does for the user, in our own wording, code and look. Nothing is copied. Owner offered to
supply screenshots and behavior notes from the paid version; that is the best source for exact behavior (see "What would help").

Status words: HAVE = built, PART = built but thinner than the reference, HELPER = needs the root helper (T009, in progress),
TODO = not started.

| Reference feature | Our state | What "matching quality" means | Needs helper |
| --- | --- | --- | --- |
| Charge limiter (slider or typed value, 50-80% advice) | PART: Limit popover with chips 50-100, saved only | Slider plus typed value, dashed sailing range on it, advice text, honest live state | yes (building) |
| Sailing mode (resume only at limit minus 0-15%) | HAVE (2026-11-15): off = held at the limit (resume 1 pt below); on = user difference 0-15 from Settings and the Limit popover, dashed marker only while sailing, off during Top Up, status "Sailing 75–80%". Calibration not built | User range 0-15, dashed marker, off during Top Up and calibration, status shows "Sailing" | yes |
| Discharge / Automatic discharge | TODO | Button plus auto mode when limit is below level; adapter cut until the target | yes |
| Top Up (once to 100%, ends on unplug) | PART: toggle saved, policy built | Works end to end, returns to the old limit on unplug | yes |
| Heat protection (pause above a max temperature, at least 5 min) | HAVE (2026-11-15, not yet tried with a warm battery): battery temperature from SMC TB0T-TB2T (matches B0AT deci-Kelvin), 5 min pause renewed while hot, 5 min minimum charge after, same helper cut as a hold, applies during Top Up, never at or below the 5% floor, "Paused: battery is 36 °C" | Max temp setting (default 35 C), 5 minute minimum pause. This Mac does not report battery temperature in the battery entry; need another read-only sensor key or mark unsupported | yes |
| Calibration mode (100% -> 10% -> 100% -> limit, monthly, schedulable) | TODO (T011) | Cycle with progress, pause heat protection, handle macOS own calibration | yes |
| Schedule (set limit, calibrate, top up, pause, discharge, power mode) | TODO (T011) | Seven actions, repeat options, catch-up after sleep | yes |
| Stop charging in sleep | TODO | Optional pre-sleep hold; our safe default restores the adapter before sleep, so this needs its own tested path | yes |
| Keep limit after quit | TODO | Helper keeps the hold when the app closes; resets at power off | yes |
| MagSafe LED control (green at limit, orange charging) | PART (2026-11-16): "Indicate charge limit" built, off by default. Helper v4 writes ACLC 3/4 only on a 90 s lease, re-writes it each second when macOS changes it, hands it back on every exit. Write and macOS overwrite hardware-verified by the probe (`docs/spikes/led-write-probe-plan.md`); the app-side feature was tried on the owner's Mac on 2026-11-16 (green at the limit, back to orange when the setting is turned off, corrected about 1 s after a replug, sleep/wake works: see the probe plan results). Blink orange during discharge, LED always off / off during sleep not built | Heat-pause orange and a charge-state change (pause to charging) still untested on hardware | yes |
| Low Power Mode control (per power source) | TODO | Always off / on / battery only / adapter only; energy mode on newer chips | yes |
| Live status icons (charging, paused, discharging, on battery) | PART: glyph has plug, bolt, pause bars; paused never triggers | Drive pause and discharge states from the runner | yes |
| Disable sleep until the limit is reached | PART: "Until limit reached", display on and re-enable at level are built; mute and lock-on-lid left out (no safe public API) | Mute and lock-on-lid options | no |
| Sleep control (30 min / 1 h / 3 h / forever / custom, re-enable at 5-95%, end on unplug) | HAVE: chips 15 m to 8 h and forever, custom minutes or hours, re-enable at 5-95%, end on unplug | Done | no |
| Hardware battery percentage next to the macOS one | HAVE: setting adds "Battery reports 99.4%" in the panel header and "80% (99.4%)" in the menu bar; "--" when unreadable | Done | no |
| Menu bar customization (icons, live values, spacing 0-20, update 2-20 s, right-click actions) | HAVE (untested on screen): preview, glyph on/off and 5 styles, 11-item catalog in 4 groups, Reset and Clear all, spacing 0-20, update 2-20 s (drives the sampler), right-click extras. Not built: macOS battery condition item, low-power tint, status items | Item catalog, update interval, spacing, right-click actions | no |
| Popover customization (add, remove, reorder widgets) | HAVE (untested on screen): Edit button, drag handles, show/hide, Reset, order saved; settings Show on startup, Show percentage, Open in edit mode | Edit mode on the Battery screen | no |
| Power flow (adapter, battery, Mac; SoC, Display, USB, Other; hide under 1 W; weak charger case) | PART: weak-charger warning, SoC/USB/Other/Charger loss rows under 1 W hidden, dash when not reported. This Mac reports only USB out and charger loss, so SoC and Other stay dashes (keys not found; not verified on real hardware). Animated map built 2026-11-15 (glass tiles, ribbons sized by watts, particles, distinct charging / idle / on battery / weak charger / no data states, fork to stream tiles plus a "Rest of Mac" tile); not yet seen on screen | Add breakdown where macOS reports it; weak-charger state; hide small streams | no |
| Apps using significant energy (Low, Medium, High thresholds, background option, Quit button) | HAVE: Low 5% / Medium 20% / High 40% CPU threshold, background toggle, polite Quit (never Finder, Dock or Apple Cart), max 5 rows. Based on CPU, not energy impact (not public) | Done | no |
| Apple Shortcuts actions (get percent, limit, state, temperature; set limit; pause; top up; discharge; LED; calibration) | PART: 4 read actions built (App Intents, metadata generated, not run in the Shortcuts app) and listed in Settings with Open Shortcuts; write actions listed as needing the helper | App Intents for each | read actions no, write actions yes |
| Fast user switching | n/a for now | Install per user; note in docs | no |

## Order

1. Now, no helper needed: Keep awake / sleep control parity, apps-using-energy parity, hardware percentage, menu bar and popover options,
   power flow breakdown, Shortcuts read actions.
2. With the helper (in progress): limiter, sailing range, top up, discharge and automatic discharge, status icons, keep after quit.
3. Then: heat protection (after a safe temperature read exists), calibration and schedule, stop in sleep, Low Power Mode, MagSafe LED (indicate
   charge limit built; blink and off modes still need a probe), Shortcuts write actions.

## What would help from the owner's paid copy

Screenshots of each Settings page and of the popover in its states (charging, held, discharging, calibrating, heat paused), plus a note of
exactly what the MagSafe LED and menu bar icon show in each state. We use these only to match behavior. No license key or app files are needed.

## Behavior notes from the owner's paid copy (screenshots, 2026-11-15; our wording, behavior only)

Popover
- The charge bar is also the limit control: a handle at its right end is dragged to set the limit; a dashed marker inside the bar shows the lower
  edge of the sailing range; a small sailing glyph sits on the bar; the plug and pause bars show the state. Limit pill top left ("Limit: 100%"),
  Top Up pill and a grid button top right (opens the full window).
- Power flow: adapter -> Mac, then the Mac side forks into SoC, USB and Other ribbons with their watts; a "more" tile holds the rest.
- "Using Significant Energy" card at the bottom lists app names with icons.
- Popover settings: Show on Startup, Show Percentage, Open in Edit Mode.

Full window (sidebar: Dashboard; Battery Care: Charge Control, Sleep Behavior, Energy Use; Automations: Schedule, Shortcuts; Appearance: Popover, Menu Bar, Other)
- Dashboard: top strip of live watts (adapter, Mac, battery, SoC, USB, other); cards for Battery Specs (current, voltage, power, system load, low power
  mode, charge in mAh), Battery Health (design and maximum capacity in mAh and %, macOS condition, cycles), Power Adapter Specs (current of max, voltage of
  max, power of max, name, manufacturer, serial); charts for battery level (with the limit as a dashed line), temperature, power consumption with a
  time-range chip and time remaining, maximum capacity over time, and battery cycles over time; right column: apps using energy, last calibration with a
  Start button, manual sleep control with a Prevent button. Temperature shown in the user's unit.
- Charge Control: limit as a typed number; "Allow charge limits below 80%" toggle with a warning icon; Automatic Discharge toggle; Sailing Mode toggle with a
  "Difference: N %" field and the result line "Will sail to X%"; Heat Protection toggle with Max Temp field and the current temperature; Calibration
  with a four-step strip (charge to 100%, discharge to 10%, charge to 100%, discharge back to the limit), an "After macOS calibration" choice, and the
  last calibration date.
- Sleep Behavior: "Prevent overcharging during sleep" choice (default: disable sleep until the charge limit, marked recommended); manual sleep control
  with a "re-enable sleep at" slider (5-95%, default 20%, tick marks) and a "when unplugged" toggle; advanced settings folded away.
- Energy Use: Low Power Mode choice; background dashboard updates toggle; "Show apps above" usage level (Medium = macOS default) and "include background processes".
- Schedule: task list with add and templates, catch-up-on-missed-tasks toggle, task history.
- Shortcuts: a table of actions with one-line descriptions plus an "Open Shortcuts" button: Top Up, Pause Charging (sets the limit to the current %),
  Start Discharge, Start Calibration, Set Charge Limit, Get Battery Percentage, Get Charge Limit, Get State, Get Temperature, Set MagSafe LED,
  Set Low Power Mode, Set High Power Mode.
- Menu Bar: a preview of the selected items; a catalog in groups (main icon style, icon options such as show percentage and a low-power tint, battery
  health, battery specs incl. hardware percentage and temperature, power adapter specs, status items) with Reset and Clear All; spacing slider 0-20.
- Other: show Dock icon, reduce transparency, restore window layout, appearance (system, light, dark), MagSafe LED (setting, indicate charge limit,
  blink orange during discharge).

## MagSafe LED rules to match (AlDente, public docs, noted 2026-11-16)

Source: https://apphousekitchen.com/aldente-overview/features/ (MagSafe 3 MacBooks). Setting: "Indicate Charge Limit", optional "Blink Orange during Discharge", LED "Always Off" / "Off During Sleep".

- Limit reached or above it: green.
- Paused because of Sailing Mode: green (ours today shows orange while sailing, see the battery page note).
- Paused by "stop charging when sleeping" or "when app closed" before the limit: orange.
- Paused by heat protection: orange.
- Top Up: green once 100% is reached.
- Calibration: green when done and the limit is reached.

Built (2026-11-16) as "Indicate charge limit" in Settings > Battery, off by default (`Core/MagSafeLED.swift` LEDPolicy, `HelperCore/LEDGuard.swift`): limit reached or above it and Sailing green, heat pause orange, Top Up green once at 100%, charging toward the limit left to macOS. Stop-in-sleep and app-closed pauses and calibration are not built in this app, so they have no rule. Not built: Blink Orange during Discharge (needs its own timing test), LED Always Off / Off During Sleep (values unknown; separate probe with the owner). Restore limit: ACLC has no "macOS decides" value, so handing back writes the last value macOS set and stops correcting; macOS rewrites it on its next event.
