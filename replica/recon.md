# Recon map (merged, clean-room)

Core loop: glance at the menu bar to see battery and system state, open the panel to adjust battery care or run a quick upkeep tool, close it. Every tool is optional and off until the owner turns it on.

Platform: native macOS menu bar app (SwiftUI + AppKit), notarized direct download. No account, no server, local data only.

## Screens

| ID | Screen | How you get there | Purpose | Key components | States |
| --- | --- | --- | --- | --- | --- |
| S01 | Menu bar item | always | icon plus optional live readouts | status item, readout text | normal, charging, paused (with reason), on battery, helper broken |
| S02 | Panel: Battery tab | click S01 | limit slider, current state, why charging is paused, top up, discharge, power flow, details | slider, state pill, flow diagram, graphs | helper missing, limit active, paused by heat, sailing, discharging, unsupported Mac |
| S03 | Panel: System tab | panel tab | stats, keep awake, fan safe mode, quick toggles, volume guard, Bluetooth-in-sleep | gauges, toggle rows, timer menu | tool off (empty state with Turn on) |
| S04 | Panel: Clean tab | panel tab | uninstaller drop zone, cleaner, disk map, update checks, DNS flush | drop zone, scan list, treemap | needs Full Disk Access, scanning, results, nothing found, error |
| S05 | Panel: Clipboard & Tools tab | panel tab | history, OCR, QR, break reminders, cleaning mode, clear notifications | searchable list, action buttons | empty history, paused, permission needed |
| S06 | Settings: Features | panel gear or Cmd-, | switch each tool on/off; reorder or hide tabs; compact mode | switch list grouped by tab | all off (first run) |
| S07 | Settings: Permissions | Settings | which tool uses which permission; drop unused | table, Open System Settings buttons | granted, missing, unused |
| S08 | Settings: Battery | Settings | heat threshold, sailing range, calibration, schedule, MagSafe light, sleep behavior | steppers, schedule list | no tasks (empty with Add task) |
| S09 | Settings: General | Settings | launch at login, updates, export/import not picked, about, debug log | toggles | update available |
| S10 | Helper install / repair sheet | enabling a battery or fan tool, or after macOS update breaks it | explain why admin is needed, install, verify | explainer, Install button, progress | installing, failed with retry, verified |
| S11 | First run | first launch | 2 screens max: what the app is, pick a starting set of tools; skippable | cards with switches | skipped |
| S12 | Cleanup preview sheet | uninstall or clean | list every file to move to Trash with sizes; confirm | checklist, total size | nothing found, partial selection |
| S13 | Region capture overlay | OCR or QR shortcut | select a region; result copied with a toast | crosshair overlay, toast | no text found, permission missing |
| S14 | Break reminder overlay | timer | gentle full-screen or banner reminder with snooze | overlay, snooze | skipped, snoozed |
| S15 | Cleaning mode overlay | tool button | black screen, input locked, clear exit instructions | overlay, exit hint | active |

## Flows (happy path clicks in brackets)

- F01 First run to charge limit: S11 pick Battery [2] -> S02 drag limit [1] -> S10 install helper [2 + admin prompt] -> S02 shows limit active. Edge: unsupported Mac, admin refused, macOS blocks charging control.
- F02 Top up before a trip: S01 -> S02 Top up [2]. Ends on unplug. Edge: heat protection active (panel says so).
- F03 Scheduled action: S08 Add task (raise limit Friday 7:00) [4]; missed while asleep -> runs on wake with a note.
- F04 Uninstall an app: drag app onto S04 drop zone [1] -> S12 review [1] -> Move to Trash with Undo toast. Edge: app running (offer quit), protected system app (refuse).
- F05 Clean caches: S04 Scan [1] -> S12 review [1] -> Trash. Edge: nothing to clean.
- F06 Copy text from screen: shortcut -> S13 drag region -> toast "Copied". Edge: Screen Recording not granted -> explain and link.
- F07 Clipboard history: shortcut or S05 -> search -> Return pastes. Edge: concealed item never stored.
- F08 Helper broken after macOS update: S01 shows warning -> S10 Repair [1 + admin].
- F09 Remove the app: Settings > Remove helper and reset battery to 100% -> then drag to Trash.

## Components

Status item with readouts; tabbed panel; section header with reorder/hide; toggle row (title, description, permission chip, switch); state pill (active, paused-with-reason, warning); slider with value field; stepper; gauge; sparkline/graph; flow diagram; drop zone; scan result checklist; treemap; searchable list with pin; toast with Undo; explainer sheet; full-screen overlay; permission table.

## Inferred data model (all local)

- FeatureState: id, enabled, tab, order, hidden. Evidence: feature switches pattern. Confidence: high.
- BatteryPolicy: limit (20-100), sailingRange, heatThresholdC, stopInSleep, keepAfterQuit, magsafeMode, dischargeTarget, topUpActive. Confidence: high.
- ScheduleTask: id, action (setLimit, topUp, calibrate, pause, discharge, lowPower), value, recurrence, nextRun, lastRun, catchUp. Confidence: high.
- BatterySample: timestamp, percent, hwPercent, temperatureC, watts, cycles, maxCapacity (24h ring buffer). Confidence: medium.
- ClipboardItem: id, kind (text, url, image, color), content or file ref, sourceApp, copiedAt, pinned. Never created for concealed/transient pasteboard types. Confidence: high.
- AwakeSession, BreakSchedule, FanPolicy (minimum offset above system curve only), Readout config. Confidence: medium.
- Settings stored in UserDefaults; clipboard history and battery samples in a local store under Application Support; nothing leaves the Mac.

## Cannot be cloned / skipped

See `skip` and `later` rows in features.csv: server features, outside data feeds, third-party product integrations, licensing.

## Size

15 screens, 9 flows, 7 entities. Hard parts: (1) privileged helper controlling charging and fans, secured to accept only the signed app, kept working across macOS updates, and whether the newest macOS still allows charge control at all; (2) cleaner and uninstaller safety with Full Disk Access; (3) energy discipline so the app itself is not a battery drain. Size: M to L.
