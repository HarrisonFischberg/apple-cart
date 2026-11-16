# Battery feature parity plan

Written 2026-11-15 from the public feature page of a reference battery app (AlDente, apphousekitchen.com/aldente-overview/features/).
Clean-room rule: we match what each feature does for the user, in our own wording, code and look. Nothing is copied. Owner offered to
supply screenshots and behavior notes from the paid version; that is the best source for exact behavior (see "What would help").

Status words: HAVE = built, PART = built but thinner than the reference, HELPER = needs the root helper (T009, in progress),
TODO = not started.

| Reference feature | Our state | What "matching quality" means | Needs helper |
| --- | --- | --- | --- |
| Charge limiter (slider or typed value, 50-80% advice) | PART: Limit popover with chips 50-100, saved only | Slider plus typed value, dashed sailing range on it, advice text, honest live state | yes (building) |
| Sailing mode (resume only at limit minus 0-15%) | PART: fixed 3 pt hysteresis in ChargePolicy | User range 0-15, dashed marker, off during Top Up and calibration, status shows "Sailing" | yes |
| Discharge / Automatic discharge | TODO | Button plus auto mode when limit is below level; adapter cut until the target | yes |
| Top Up (once to 100%, ends on unplug) | PART: toggle saved, policy built | Works end to end, returns to the old limit on unplug | yes |
| Heat protection (pause above a max temperature, at least 5 min) | TODO | Max temp setting (default 35 C), 5 minute minimum pause. This Mac does not report battery temperature in the battery entry; need another read-only sensor key or mark unsupported | yes |
| Calibration mode (100% -> 10% -> 100% -> limit, monthly, schedulable) | TODO (T011) | Cycle with progress, pause heat protection, handle macOS own calibration | yes |
| Schedule (set limit, calibrate, top up, pause, discharge, power mode) | TODO (T011) | Seven actions, repeat options, catch-up after sleep | yes |
| Stop charging in sleep | TODO | Optional pre-sleep hold; our safe default restores the adapter before sleep, so this needs its own tested path | yes |
| Keep limit after quit | TODO | Helper keeps the hold when the app closes; resets at power off | yes |
| MagSafe LED control (green at limit, orange charging) | TODO (T012) | Needs a write probe first; the LED key reads here, never written | yes |
| Low Power Mode control (per power source) | TODO | Always off / on / battery only / adapter only; energy mode on newer chips | yes |
| Live status icons (charging, paused, discharging, on battery) | PART: glyph has plug, bolt, pause bars; paused never triggers | Drive pause and discharge states from the runner | yes |
| Disable sleep until the limit is reached | PART: "Until limit reached", display on and re-enable at level are built; mute and lock-on-lid left out (no safe public API) | Mute and lock-on-lid options | no |
| Sleep control (30 min / 1 h / 3 h / forever / custom, re-enable at 5-95%, end on unplug) | HAVE: chips 15 m to 8 h and forever, custom minutes or hours, re-enable at 5-95%, end on unplug | Done | no |
| Hardware battery percentage next to the macOS one | HAVE: setting adds "Battery reports 99.4%" in the panel header and "80% (99.4%)" in the menu bar; "--" when unreadable | Done | no |
| Menu bar customization (icons, live values, spacing 0-20, update 2-20 s, right-click actions) | PART: readout choice plus 5 glyph styles | Item catalog, update interval, spacing, right-click actions | no |
| Popover customization (add, remove, reorder widgets) | TODO | Edit mode on the Battery screen | no |
| Power flow (adapter, battery, Mac; SoC, Display, USB, Other; hide under 1 W; weak charger case) | PART: adapter, Mac, battery ribbons | Add breakdown where macOS reports it; weak-charger state; hide small streams | no |
| Apps using significant energy (Low, Medium, High thresholds, background option, Quit button) | HAVE: Low 5% / Medium 20% / High 40% CPU threshold, background toggle, polite Quit (never Finder, Dock or Apple Cart), max 5 rows. Based on CPU, not energy impact (not public) | Done | no |
| Apple Shortcuts actions (get percent, limit, state, temperature; set limit; pause; top up; discharge; LED; calibration) | TODO | App Intents for each | read actions no, write actions yes |
| Fast user switching | n/a for now | Install per user; note in docs | no |

## Order

1. Now, no helper needed: Keep awake / sleep control parity, apps-using-energy parity, hardware percentage, menu bar and popover options,
   power flow breakdown, Shortcuts read actions.
2. With the helper (in progress): limiter, sailing range, top up, discharge and automatic discharge, status icons, keep after quit.
3. Then: heat protection (after a safe temperature read exists), calibration and schedule, stop in sleep, Low Power Mode, MagSafe LED (write
   probe with the owner present first), Shortcuts write actions.

## What would help from the owner's paid copy

Screenshots of each Settings page and of the popover in its states (charging, held, discharging, calibrating, heat paused), plus a note of
exactly what the MagSafe LED and menu bar icon show in each state. We use these only to match behavior. No license key or app files are needed.
