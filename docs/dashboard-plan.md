# Battery dashboard window: plan

Written 2026-11-15. Source of the behavior: the owner's screenshots of the reference app (see docs/battery-parity.md). We copy what the screen
tells the user, not its look, wording or code.

## What it is

A resizable window, opened from the grid button in the panel header (and from Settings). It is the full-size view of everything the Battery
tool knows. The panel stays the quick view. The window has a sidebar and a main area:

- Sidebar: Dashboard, then Charge Control, Sleep Behavior, Energy Use, Schedule, Shortcuts, Popover, Menu Bar, Other. Several of these already exist
  as pages in the Settings window; this window and Settings must share the same page views, not duplicate them. Decision: the dashboard IS the
  Settings window with a new first page called Dashboard and the Battery tool's pages grouped under "Battery". One window, one sidebar.
- Dashboard page: a top strip of live watts, then cards and charts.

## Cards and charts, and whether this Mac can fill them

| Piece | Source | Available on this Mac (checked read-only) |
| --- | --- | --- |
| Live strip: adapter, Mac, battery, SoC, USB, other watts | PowerTelemetryData, adapter and battery power | adapter, Mac, battery yes; SoC, USB, other depend on the flow builder's inspection |
| Battery Specs: current, voltage, power, system load, low power mode, charge mAh | InstantAmperage, Voltage, SystemLoad, pmset, RemainingCapacity | yes |
| Battery Health: design and maximum capacity (mAh and %), macOS condition, cycles | DesignCapacity, AppleRawMaxCapacity, NominalChargeCapacity, CycleCount; condition from system_profiler | yes (condition needs a one-time read) |
| Power Adapter Specs: current of max, voltage of max, power of max, name, maker, serial | AdapterDetails (Name, Manufacturer, SerialString, Current, AdapterVoltage, Watts) | yes, all present |
| Battery level chart with the limit as a dashed line | BatteryHistory (24 h today) plus ChargeLimitSettings | level yes; limit line needs history of limit changes |
| Time to full / time remaining | TimeRemaining and charge rate | partly (macOS often reports none); compute from watts, label as estimate |
| Battery temperature and chart | none found | **no** (no Temperature key). Needs another read-only sensor key or the card shows "Not available on this Mac" |
| Power consumption chart with a range chip (15 m, 1 h, 24 h) | system watts samples | yes, needs longer stored history |
| Maximum capacity over time | AppleRawMaxCapacity samples | needs a daily stored sample; only starts from install |
| Battery cycles over time | CycleCount samples | needs a daily stored sample; only starts from install |
| Last calibration, Start Calibration | calibration runner | blocked on the helper and T011 |
| Manual sleep control (Prevent) | Keep awake | yes (sleepenergy builder) |
| Apps using significant energy | energy users list | yes (sleepenergy builder) |

## Data work first (this is the real prerequisite)

1. **Longer history store.** Today BatteryHistory keeps 24 hours in memory and loses it on quit. The dashboard needs: 24 h at fine grain, 30 days
   at hourly grain, and daily samples of maximum capacity and cycle count kept for years. Store locally under Application Support as a small
   file (JSON or SQLite), written in the background with a size cap, covered by "Delete all app data" and listed in docs/data-inventory.md.
   Gaps stay gaps (no invented points).
2. **Limit history.** Record each change of the charge limit with a time so the level chart can draw the dashed line.
3. **Units.** One setting for temperature unit (C or F), used everywhere.

## Build order (each step ships on its own)

1. History store and its tests (pure, time-injected). No UI.
2. Dashboard page shell: top watts strip plus the three spec cards (Battery Specs, Battery Health, Adapter Specs). All values exist today.
3. Charts: battery level with the limit line, power consumption with a range chip, then capacity and cycles history (they start sparse; show an
   honest "collecting data since <date>" note).
4. Right column: apps using energy, manual sleep control, calibration card (disabled with a reason until T011).
5. Temperature card: ship as "Not available on this Mac" unless a read-only sensor key is found (separate small spike, read-only SMC probe).
6. Grid button in the panel header opens Settings on the Dashboard page.

## Dependencies and conflicts

- Do after the limiter, flow and sleep builders merge, because it touches the same Battery screen files and the Settings sidebar.
- Charts: use Swift Charts (system framework, no dependency).
- Must work at the window's smallest size (680 by 460): cards reflow to one column; charts keep readable labels; Reduce Motion, VoiceOver
  summaries for every chart ("Battery level, 100 percent now, held at 80 percent limit").

## Risks

- The history store grows: cap size and prune by grain; test pruning.
- Charts with sparse data look broken: always show the empty state text and the date collection started.
- Reading `system_profiler` for macOS condition is slow: read once at launch in the background and cache.
- Temperature may never be available on this model; do not fake it.

## Test plan

Pure tests for the history store (append, prune, grain roll-ups, gaps, size cap, delete-all). Preview renders for every card in every state
(charging, held, discharging, no data) in light and dark, then a live walk-through with the owner at the Mac.
