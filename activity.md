# Activity log

## 2026-11-14 — scaffold

- Created project skeleton under the `new-app` skill.
- Next: Phase 0 intake and tool-environment verification.

## 2026-11-14 Phase 2 (Opus)

- REA triage on all five references (public marketing pages for native Mac apps; triage only, no binaries in scope). Evidence kept in the lab folder, outside this repo.
- Feature catalogues and public complaints gathered per source; merged into 107 de-duplicated capabilities across 11 groups.
- Comparison published for owner pick (private artifact). STOP: waiting on owner approval of the comparison and the a-la-carte picks before writing replica/ spec.

## 2026-11-14 Phase 2B (Opus)

- Owner approved final picks: 34 features (added battery schedule; dropped jiggler; connection map and dictation to Later; fan control safe mode; clipboard history skips sensitive items).
- Merged spec written to replica/ (recon.md, features.csv, prompts/, decisions.md); sanitized docs/rea-findings.md.
- Brand sweep with --include-replica: clean. Source names removed from docs/tool-environment.md and docs/intake-notes.md.
- Next: erase lab folder (owner yes), then Phase 3 blueprint.

## 2026-11-14 Phase 3 (Opus)

- Blueprint, PRD (26 tasks, 6 milestones), data inventory and launch blockers written. replica-architect output adapted to native (replica/architecture.md).
- Researched macOS 27 charge-control reports; spike T002 gates battery control.
- STOP: waiting on owner approval of blueprint, minimum OS, and installing XcodeGen.
- Owner approved blueprint, macOS 26+ Apple silicon, and XcodeGen install (2.46.0). Next: Phase 3B design directions (Sonnet builds).

## 2026-11-14 Phase 3B (Sonnet builds)

- Impeccable concept-seed run (seed:a6ed928998647bf4). Three concepts built in worktrees ../apple-cart-ui-1..3 (branches ui-1..3, local only): C1 Tape (assigned), C2 Rams (pick), C3 Course (challenger). 12 screenshots (light/dark, Battery/System) in docs/design/screenshots/.
- Harness: SwiftUI rendered through an NSWindow (design/concepts/shared). No browser preview or Playwright used. Impeccable detector not run (native target; it reads HTML/CSS). critique/audit skipped in lean mode until a direction is picked.
- Not exercised: dragging, arrow keys, VoiceOver in any concept.
- Lesson: do not pass isolation worktree to builder subagents that must work in pre-made worktrees (cost one wasted round).
- STOP: waiting on owner pick.
- Owner asked to closely mimic the reference display (Source A) after seeing C1-C3. Looked at its public live demo in the in-app browser (read only, public page). Built C4 Tiles in ../apple-cart-ui-4 (ui-4): 6 screenshots. Awaiting approval.
- Owner approved C4 Tiles ("do"). Merged ui-4 into main (local, not pushed); removed worktrees; deleted merged branches ui-4, ui-base, phase-2/spec; kept ui-1..3. Plan docs updated for launcher IA. DESIGN.md + .impeccable/design.json written by documenter (Phase 3C). Next: Phase 4 (Sonnet, T001 and the T002 spike).

## 2026-11-14 Phase 4 start (Sonnet)

- Ralph quickstart cloned (owner yes), reviewed, adapted into ralph/ (6-iteration cap, Sonnet pinned, no network/push). Not run yet. /goal not available; bounded condition lives in PROMPT.md.
- T001 done: XcodeGen project, Core + HelperProtocol modules, status item app. xcodebuild BUILD SUCCEEDED (only an OS tool warning, none from our code); 4 tests pass; app ran 3 s, LSUIElement true, ad-hoc signed. Menu bar icon NOT seen (no screen capture permission here).
- T002 partial: public research + read-only probes in docs/spikes/charge-control.md. Found AlDente Pro helper installed and Vorssaint running on this Mac, so a write test needs them quit and reset first. No battery or system write was made.
- Branch phase-4/build, local only. Next: owner decisions for T002; Ralph can run tasks that do not need the owner (T003+).

## 2026-11-14 T003 (Sonnet)

- Feature switches: Core has FeatureRegistry (off by default, start on enable, stop and release on disable, ignores switching on a tool that is not built), SettingsStore (UserDefaults, unknown ids dropped), FeatureFamily; UI module has Settings > Features view; app menu has Settings…. 8 registry tests + 4 earlier all pass; xcodebuild BUILD SUCCEEDED, no warnings from our code.
- One test failed on the first run because the test itself held the tool alive; fixed by not holding it, the release assertion is unchanged.
- UIPreview dev tool renders views light/dark (docs/design/screenshots/build/). Offscreen windows are inactive, so switch tint cannot be seen there; confirm the on-state color in the running app.
- Every switch currently reads Not built yet in the app (no tool is registered until its task).

## 2026-11-14 T004 (Sonnet)

- Core: LauncherModel (order, hide, search, arrow-key neighbours) and PanelModel (route, keep open, reset on close), persisted via SettingsStore; 7 new tests, 15 total pass.
- UI: PanelView (420x560, header with back, search, overflow menu: Keep open, Settings, Collapse, Quit), 4-column tile grid, drag to reorder, context menu (Open, Hide), arrow/Return/Space keys, Add tools tile, empty and no-match states, placeholder for tools with no view. Only tools that are on show; off tools are not dimmed. No shortcut hints yet (no tool has a shortcut).
- App: PanelController with non-activating NSPanel, global and local mouse monitors for outside click, Esc closes, positioned under the status item; right click shows Settings/Quit. xcodebuild BUILD SUCCEEDED; app launched and stayed running.
- NOT verified live: no accessibility or screen permission here, so the status item click, click-inside, outside-click and Esc were never exercised. Offscreen renders (t004-launcher/empty, light and dark) checked by eye. Owner should click the icon once.

## 2026-11-14 T005 (Sonnet)

- Core: Permission (screen recording, full disk access, accessibility, notifications; each names its tools, reason and System Settings pane), PermissionChecker (read-only), PermissionsModel (active users, unused-but-granted). 5 new tests, 20 total pass.
- UI: Permissions tab beside Features in the Settings window. App: SystemPermissionChecker uses preflight calls only, so nothing prompts at launch. xcodebuild BUILD SUCCEEDED; light/dark previews checked.
- Not verified live: real statuses and Open Settings deep links (no screen or accessibility permission here). Full Disk Access check probes a Safari file, shows Checking if absent. Requests themselves are done by each tool's task, naming the tool.

## 2026-11-14 T006 (Sonnet)

- Core: BatteryReading (parsed from AppleSmartBattery properties), BatteryHistory (24 h rolling), EnergyUsers (ps, grouped by app), BatterySampler (timer runs only while a holder exists). 6 new tests, 26 total pass.
- UI: BatteryView (percent, state, power flow, true charge, capacity vs new, cycles, temperature, system watts, charger, graph, busiest apps). Opens from the Battery tile; it holds the sampler only while the panel is open on that view (PanelModel.isOpen).
- Checked against this Mac: percent 80, cycles 98, plugged in, not charging, battery 0 W all match pmset/ioreg. True charge 79.0% comes from raw capacity values.
- Findings: macOS 27 exposes no Temperature key, so the row says so. system_profiler shows Maximum Capacity 96%, our measured raw ratio is 92% (labelled Capacity vs new), they differ by definition.
- Decision: the 24 h graph only records while a view or readout holds the sampler (T007 menu bar readout will hold it), so it shows real gaps instead of sampling in the background. Revisit if the owner wants a background history option.
- Not seen live: the running app (no click access here).
- Owner decision (11-14): 24 h graph records only while a view or readout holds the sampler. No background sampling.

## 2026-11-14 T007 (Sonnet)

- Core: MenuBarReadout (icon only, percent, percent and watts; icon follows charge), ReadoutSettings (observable, saved), FirstRunModel (2 steps, finish from either). 4 new tests, 30 total pass.
- UI: first-run overlay in the panel (Skip on both screens, one click), Settings > Menu bar tab. App: StatusReadout updates the status item from the sampler and holds it only while the Battery tool is on and a text readout is chosen; otherwise the icon is static and nothing samples.
- Timing: the sampler polls every 5 s, so a power change shows within 5 s plus read time. Not measured live.
- Not seen live: the real status item text (no screen or accessibility access); first-run renders checked light and dark. First-run Choose tools opens Settings and leaves the panel on screen 1.

## 2026-11-14 T008 (Sonnet)

- Core: KeepAwake (IOKit power assertion; timer, stop at a battery level only while unplugged, optional display on; replaces rather than stacks; refusal is reported), SystemSampler (CPU from tick deltas, memory used = active + wired + compressed, thermal, uptime; samples only while held). 9 new tests, 39 total pass, including one that runs `pmset -g assertions` and sees the assertion appear on start and vanish on stop.
- UI: Keep awake view (presets 15 min to until I stop, display toggle, battery level stepper, live countdown, last stop reason) and System view. Turning the Keep awake tool off ends the session. Last-used choices are remembered.
- Not seen live: the running app's click path (no screen or accessibility access). System readings looked plausible in the preview (CPU 20%, 19.0 of 32.0 GB).
- Limit: the level rule polls the battery every 30 s, so it can overshoot by up to 30 s of drain.

## 2026-11-14 T013 (Sonnet)

- Core: QuickToggles (hidden files, all extensions, Dock auto-hide, desktop icons) over CFPreferences, then restart Finder or Dock; state is re-read after each change so the switch shows what the system holds. VolumeGuard lowers volume to the owner's limit when the default output device changes (CoreAudio listener, no timer, never raises). 6 new tests, 45 total pass.
- Checked read-only on this Mac against `defaults read`: all four states match (autohide on, others at macOS defaults). No toggle was flipped for real, because that restarts Finder and Dock on the owner's machine; the write path is covered by fake-preference tests only.
- Volume read worked (0.69 on this Mac). Volume lowering on a real device change not exercised.
- Bluetooth off in sleep not built: no public API. Recorded in docs/launch-blockers.md.
- Not seen live: the running app (owner is away from the Mac; no screen access here).
- Owner decision 2026-11-14: Bluetooth off in sleep dropped for v1 (option 1). T013 marked done without it.

## 2026-11-14 T018 updates, T015 flush DNS
- T018: Core/Updates.swift (parsers, UpdateChecker, ProcessRunner), UI/UpdatesView. Runs only on "Check now". Homebrew uses HOMEBREW_NO_AUTO_UPDATE=1 (local list only). Real run matched brew; softwareupdate said none.
- T015: Core/FlushDNS.swift + FlushDNSView. New FeatureID flushDNS (17th tool; count test updated). Interim AdminPromptRunner (osascript admin dialog) because the T009 helper does not exist yet. Real flush not run.
- 50 tests pass, build clean, previews t015/t018 in docs/design/screenshots/build.
- Data flow to record: `softwareupdate --list` contacts Apple's update service on user request.
- 11-14 live check (owner at Mac): Flush DNS showed the macOS password dialog then Done. Updates tile not reported on. No system log entry for the flush.
- 11-14 live check: owner's screenshot of the Updates tile in the running app (dark mode, checked 17:35) shows macOS none and the same 8 Homebrew formulae.

## 2026-11-14 T016 uninstaller
- Core/Uninstaller.swift (UninstallPolicy allowlist, UninstallerModel, Trasher/RunningApps protocols), UI/UninstallerView (drop zone, Choose an app button, preview with per-item tick, Trash, Undo). Leftovers match the exact bundle ID only (no name matching), in 11 fixed ~/Library folders; LaunchAgents deliberately skipped (loaded agents need bootout).
- Refuses com.apple.* apps, Apple Cart itself, apps outside /Applications and ~/Applications. Running app must be quit first. App is trashed first; if that fails its files are left alone. Undo stays until next action.
- 56 tests pass, build clean. Previews t016. Fixed a stacked-label layout bug seen in the first render.
- Not done: a real Trash move, drag-drop, the file chooser, and the Full Disk Access prompt flow were not exercised on the Mac.

## 2026-11-14 T017 cleaner + disk map
- Core/Cleaner.swift (CleanerPolicy, CleanerModel, DiskMapModel), UI/CleanerView.swift (CleanerView, DiskMapView). Cleaner covers direct children of ~/Library/Caches, ~/Library/Logs, Xcode DerivedData; skips com.apple.* caches; preview, Trash, Undo (reuses Trasher/UninstallReport). Disk map is read-only (drill down, Show in Finder), progressive and stoppable.
- Bug fixed: detached work ignored cancellation; now forwarded with withTaskCancellationHandler (test covers cancel).
- Real read-only scans: cleaner 370 items, matches du; disk map top level matched. Nothing moved. 60 tests, build clean.

## 2026-11-14 T021 break reminders + cleaning mode
- Core/Breaks.swift (BreakReminders: one sleep to the next due time, snooze 10 min, pause/resume on sleep/wake, settings in UserDefaults), Core/CleaningMode.swift (InputBlocker protocol, 5 min cap, always ends), UI/BreaksView.swift (BreaksView, CleaningModeView, CleaningOverlayView), App/BreaksSupport.swift (UNUserNotificationCenter banners with Snooze, CGEventTap blocker where holding Esc 3 s exits, overlay windows).
- Permission: Notifications asked when a reminder is first switched on; Accessibility needed for cleaning mode (added to Permission.usedBy).
- Not built: Clear all notifications (blocker logged).
- Fixed a layout bug: switch rows were centered; now label left, switch right (also fixed in Quick toggles).
- 67 tests, build clean. NOT run live: banners, event tap, overlay. Risk to remember when testing: cleaning mode locks the keyboard; the way out is Esc held 3 s or the timer (max 5 min).
- Owner decision 2026-11-14: Clear all notifications dropped for v1. T021 marked done without it.

## 2026-11-14 T019 clipboard history
- Core/Clipboard.swift (ClipboardHistory tool, LinkCleaner, PasteboardAccess), UI/ClipboardView.swift, App/ClipboardSupport.swift (NSPasteboard access, ⌘V via CGEvent, ⌃⌥⌘V plain-paste hotkey via Carbon).
- Stores text, links and images (images as PNG files). Never stores items marked concealed/transient/auto-generated or from 1Password; per-app "never store"; 7-day default retention (1-90), pinned kept, 200 unpinned cap, 100k-char text cap, 10 MB image cap. Search, pin, delete with Undo, paste, paste as plain text, tracking-parameter stripping (off by default), clear after a minute and on lock (off by default).
- History is a JSON file in Application Support (blueprint said SwiftData; JSON is smaller and has no dependency).
- Source app is the frontmost app when the change is noticed (up to 0.5 s late), so it can be wrong right after an app switch.
- Not built: "offer to clear when the tool is turned off" (use Clear history for now).
- 78 tests, build clean. NOT run live: pasteboard watching, pasting, shortcut, lock clear.

## 2026-11-14 T020 copy text + read QR
- Core/ScreenReading.swift (ScreenReader flow, VisionRecognizer, protocols), UI ScreenReadView (in ClipboardView.swift), App/ScreenSupport.swift (RegionPicker overlay, ScreenCaptureKit ScreenCapturer, Toast). Hotkeys now go through one HotKeyCenter (fixes the earlier single handler that fired on any shortcut): ⌃⌥⌘V plain paste, ⌃⌥⌘T copy text, ⌃⌥⌘Q read QR; each exists only while its tool is on.
- Image is captured in memory only and never saved. QR results are copied, never opened. Nothing is sent anywhere (Vision is on-device).
- Vision tests make the suite take about 28 s.
- NOT run live: area picker, capture, permission prompt, toast, shortcuts.
