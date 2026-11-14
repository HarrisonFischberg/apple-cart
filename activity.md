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
