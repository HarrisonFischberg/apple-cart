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
