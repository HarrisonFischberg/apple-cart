# Blueprint

Status: APPROVED by owner 2026-11-14 (Phase 3, Opus). Minimum OS: macOS 26+, Apple silicon only. Works from `replica/` only.

## 1. Stack decision

| Layer | Choice | Why | Rejected |
| --- | --- | --- | --- |
| Language / UI | Swift 6, SwiftUI for views, AppKit for the menu bar item and panel | Native look and behavior, best energy profile, owner's chosen stack | Electron/Tauri (heavier, not native), Catalyst (no menu bar control) |
| Menu bar | `NSStatusItem` plus a custom non-activating `NSPanel` | Panel stays open while clicking inside (fixes a source complaint); `MenuBarExtra` closes on interaction and can't host tabs well | `MenuBarExtra(.window)` |
| Project | XcodeGen `project.yml` plus one local Swift package `AppleCartKit` holding all logic | Project file is generated and diffable; logic is testable with `swift test` without UI | Hand-edited `.xcodeproj`, Tuist |
| Persistence | `UserDefaults` for settings; SwiftData store in Application Support for clipboard history, battery samples, schedule history | Built in, no dependency, local only | GRDB/SQLite (extra dependency), Core Data (more boilerplate) |
| Privileged work | One launchd daemon registered with `SMAppService.daemon`, talking over `NSXPCConnection` with a code-signing requirement on both ends | Apple's supported way to ship a root helper; only the signed app can talk to it | `SMJobBless` (deprecated), shelling out with `sudo` |
| Updates | Sparkle 2 (MIT), appcast and builds on the public GitHub repo's Releases | Standard for notarized direct-download Mac apps | Mac App Store (20 picks can't run sandboxed) |
| Login item | `SMAppService.mainApp` | Built in | Legacy helper apps |
| On-device vision | Vision framework (text recognition, barcode detection) | Free, offline, no vendor | Cloud OCR |
| Readings | IOKit (power sources, AppleSmartBattery registry, SMC reads), `host_statistics`, `IOPMAssertion` | System frameworks | Third-party monitoring libraries |
| Distribution | Developer ID signed, notarized DMG; optional Homebrew cask later | Owner decided after comparison | — |

**Minimum OS (approved): macOS 26 or later, Apple silicon only.** Charge control differs by OS and chip; one backend family keeps the riskiest part small. Cost: Intel Macs and macOS 15 users are excluded. Owner decides at approval.

## 2. Data model (local only; the only actor is the Mac's user, plus the root helper)

All stores live under `~/Library/Application Support/AppleCart/` or `UserDefaults` (`app` domain). Nothing is synced or sent anywhere.

| Entity | Fields (type) | Key / index | Who reads / writes | Retention |
| --- | --- | --- | --- | --- |
| FeatureState | id (String, enum `FeatureID`), enabled (Bool), tab (enum), order (Int), hidden (Bool) | id | app | until changed |
| BatteryPolicy | limitPercent (Int 20-100), sailingRange (Int 0-15), heatPauseC (Double 30-45), stopInSleep (Bool), keepAfterQuit (Bool), magsafeMode (enum off/indicate/system), dischargeTarget (Int?), autoDischarge (Bool), topUpUntilUnplug (Bool) | singleton | app writes; helper receives the effective command, never the whole policy | until changed; removing the app resets the battery to 100% |
| ScheduleTask | id (UUID), action (enum setLimit/topUp/calibrate/pauseCharging/dischargeTo/lowPower), value (Int?), recurrence (enum once/daily/weekly/monthly/yearly + weekday/day), nextRun (Date, UTC), lastRun (Date?), catchUp (Bool), enabled (Bool) | id; index nextRun | app | until deleted |
| ScheduleRun | taskID (UUID), ranAt (Date), result (enum ok/skipped/failed), note (String) | index ranAt | app | 30 days |
| BatterySample | at (Date), percent (Double), hwPercent (Double), tempC (Double), watts in/out (Double), cycles (Int), maxCapacity (Int) | index at | app | 24 hours (ring buffer) |
| ClipboardItem | id (UUID), kind (enum text/url/image/color/file), text (String?), imageRef (file name?), sourceBundleID (String?), copiedAt (Date), pinned (Bool) | id; index copiedAt, pinned | app | owner-set: 7 days default, pinned kept; never created for concealed, transient or auto-generated pasteboard types |
| AwakeSession, BreakSchedule, FanPolicy (offsetAboveSystemRPM Int >= 0), ReadoutConfig | small value types | singleton | app | until changed |

Hard constraints enforced in code, with unit tests: limit within 20-100; fan offset never negative; a cleanup run only ever moves files to Trash; one active charge command at a time (the policy engine is the single writer).

## 3. API spec (XPC between app and helper; no network API)

Protocol `HelperProtocol` (in `AppleCartKit/HelperProtocol`). The helper validates the caller's code signature (team ID + bundle ID) on every connection and rejects all others.

| Call | Does | Input | Output | Errors |
| --- | --- | --- | --- | --- |
| `version()` | handshake, compatibility | — | helper version | `outdated` |
| `capabilities()` | what this Mac/OS supports | — | `{chargeLimit, discharge, magsafe, fanWrite, closedLidAwake}` booleans + reason strings | `unsupportedHardware` |
| `setChargingAllowed(Bool)` | pause or resume charging | Bool | ok | `blockedByOS`, `notSupported` |
| `setChargeLimit(Int)` | native limit where the OS offers one | 20-100 | ok | `outOfRange`, `notSupported` |
| `setAdapterEnabled(Bool)` | discharge while plugged in | Bool | ok | `notSupported` |
| `setMagSafeLED(Mode)` | LED mode | enum | ok | `notSupported` |
| `setFanMinimum(fanIndex, rpm)` | raise fan minimum; helper clamps to >= system minimum | Int, Int | applied rpm | `outOfRange` |
| `releaseFans()` | return fans to the system | — | ok | — |
| `setClosedLidAwake(Bool)` | allow closed-lid awake | Bool | ok | — |
| `flushDNS()` | flush resolver cache | — | ok | — |
| `resetAll()` | battery to 100% charging allowed, fans released, closed-lid off; called on removal | — | ok | — |

The helper keeps no settings file and applies `resetAll()` if the app has not checked in for 10 minutes and "keep limit after quit" is off.

Local jobs (app process): policy engine tick (event-driven on power-source change, plus 60 s while plugged in), schedule runner (timer to the next task; catch-up on wake), clipboard poll (0.5 s `changeCount` check only while the tool is on), samplers (only while visible or a readout needs them).

## 4. Folder structure

```
apple-cart/
  project.yml                 XcodeGen spec (app + helper targets)
  App/                        AppKit entry, status item, panel window, Settings window
  Helper/                     launchd daemon main + plist
  Packages/AppleCartKit/
    Sources/Core/             FeatureRegistry, SettingsStore, PermissionsService, Toasts, Logging
    Sources/HelperProtocol/   XPC protocol + shared types
    Sources/Battery/          readings, PolicyEngine (pure), Scheduler, ChargeBackend
    Sources/System/           monitor, awake, toggles, volume guard, fans (client side)
    Sources/Clean/            uninstaller, cleaner, disk map, update checks
    Sources/Clipboard/        history, autoclear, link cleaner, OCR/QR
    Sources/Tools/            breaks, cleaning mode, notifications
    Sources/UI/               shared SwiftUI components and tokens
    Tests/                    one test target per module
  docs/  replica/  ralph/
```

## 5. State management

- **App-owned**: all settings and stores in section 2; UI state in `@Observable` models per tab.
- **Helper-owned**: only the hardware state it last applied; it never stores user data.
- **System-owned**: battery, fans, power assertions, clipboard. The app reads them and reconciles; the panel always shows the effective state plus the reason it differs from the setting (e.g. "Paused: battery at 41 °C", "macOS is calibrating the battery").
- **Unload rule**: turning a tool off cancels its timers, observers and samplers and releases anything it changed (fans, assertions, LED).

## 6. Vendors and data flows

| Vendor / component | Purpose | Data it receives | Recorded in data-inventory |
| --- | --- | --- | --- |
| Sparkle 2 (bundled, MIT) | update checks | nothing beyond the request below | yes |
| GitHub Releases (public repo) | hosts the appcast and DMG | IP address, user agent with app version, on each update check | yes |
| Apple notary service | notarization at build time | the build, not user data | yes |
| Homebrew (local, only if installed and the tool is on) | outdated packages | local command, no network from the app | yes |
| Mail app (user-initiated) | Send Debug Logs: opens a draft to the support address | only what the user chooses to send | yes |

No analytics, crash reporting, ads or AI provider. Adding any requires a new row first.

## 7. Parts that bite

- **Charge control on current macOS (highest risk).** Public reports (Nov 2026) show macOS 27 adds a native maximum charge limit that third-party tools now drive, and a battery calibration state during which macOS ignores any limit. Some older direct-control methods stopped working. Plan: spike T002 decides the backend before any battery-control code; the panel must show "macOS is calibrating the battery" instead of silently charging past the limit. Go/no-go: if no workable mechanism, ship the read-only battery tools and mark the control tools BLOCKED.
- **Root helper security**: code-signing requirement on the XPC connection; narrow command set; clamped inputs; no shell execution of caller strings.
- **Energy**: the app must not become a battery drain; idle target below 0.1% CPU with every tool off, measured.
- **Full Disk Access tools**: path allowlist (user Library locations by bundle ID), never system paths, Trash only, preview required.
- **Sleep/wake**: schedule catch-up, helper reconnection, audio device changes rebuild listeners cleanly.
- **Clipboard privacy**: skip `org.nspasteboard.ConcealedType`, `TransientType`, `AutoGeneratedType`; per-app exclusion list.
- **Time**: schedule times stored in UTC with the user's time zone for display; DST covered by recurrence tests.
- **Notarization / signing**: requires a Developer ID Application certificate (launch blocker until confirmed).

## 8. Feature scoring (lean, 0-3 each: evidence, impact, effort where 3 = smallest, fit with the one job)

| Feature | Ev | Imp | Eff | Fit | Total | Milestone |
| --- | --- | --- | --- | --- | --- | --- |
| Panel, switches, permissions on demand | 3 | 3 | 2 | 3 | 11 | M1 |
| Battery details + true % + power flow | 3 | 3 | 2 | 3 | 11 | M1 |
| Menu bar readouts | 3 | 2 | 3 | 3 | 11 | M1 |
| Keep awake | 3 | 2 | 3 | 3 | 11 | M1 |
| System monitor | 2 | 2 | 2 | 3 | 9 | M1 |
| Charge limit + paused reason | 2 | 3 | 1 | 3 | 9 | M2 |
| Heat protection, sailing, top up | 1 | 2 | 3 | 3 | 9 | M2 |
| Discharge, stop in sleep, keep after quit | 1 | 2 | 2 | 3 | 8 | M2 |
| Energy-hungry apps | 2 | 2 | 3 | 3 | 10 | M1 |
| Calibration, schedule | 1 | 2 | 2 | 3 | 8 | M2 |
| MagSafe light | 1 | 1 | 3 | 2 | 7 | M2 |
| Quick toggles, volume guard, Bluetooth in sleep | 2 | 2 | 3 | 2 | 9 | M3 |
| Fan safe mode | 1 | 1 | 1 | 2 | 5 | M3 |
| Flush DNS | 1 | 1 | 3 | 1 | 6 | M3 |
| Uninstaller, cleaner (Trash + preview) | 3 | 2 | 2 | 2 | 9 | M4 |
| Disk map | 1 | 2 | 2 | 2 | 7 | M4 |
| Update checks | 2 | 1 | 2 | 2 | 7 | M4 |
| Clipboard history (+ sensitive skip), auto-clear, plain paste, clean links | 3 | 2 | 2 | 2 | 9 | M5 |
| OCR, QR | 3 | 2 | 3 | 2 | 10 | M5 |
| Break reminders | 2 | 1 | 3 | 2 | 8 | M5 |
| Cleaning mode, clear notifications | 2 | 1 | 3 | 1 | 7 | M5 |

First slice (M1) = the top scorers: the shell plus everything battery and system you can read without the root helper. It proves the stack and the panel before the risky helper work.

**Later** (not in v1): outgoing connection list and map; on-device dictation.

## 9. Build order

| Milestone | Tasks (prd.md) | Screens |
| --- | --- | --- |
| M1 Vertical slice | T001-T008 | S01, S02 (read-only), S03 (partial), S06, S07, S11 |
| M2 Battery control | T009-T012 (after T002 go) | S02, S08, S10 |
| M3 System | T013-T015 | S03 |
| M4 Clean | T016-T018 | S04, S12 |
| M5 Clipboard and tools | T019-T021 | S05, S13, S14, S15 |
| M6 Release hardening | T022-T026 | S09 |
