# apple-cart — PRD

Status: APPROVED by owner 2026-11-14 (macOS 26+, Apple silicon only). Blueprint: `docs/blueprint.md`.

## Purpose

A free, private Mac menu bar app for battery care and system upkeep. Every tool is a switch, off by default, so the app stays as small as the owner's choices. Notarized direct download; no account, no server.

## Product features (34, owner-approved 2026-11-14)

Full list with priorities: `replica/features.csv`. Groups: Foundation (panel, switches, permissions on demand, readouts, updates, launch at login), Battery (12), System (7), Clean (4), Clipboard (6), Tools (3).

## Out of scope (non-goals)

- Anything needing a server, account or sync; phone companion.
- Licensing, trials, paid tiers, ads, analytics.
- Window management, keyboard remapping, capture/recording, notch island (not picked).
- Later list: outgoing connection list and map; on-device dictation.
- Mac App Store build (20 picked tools can't run sandboxed).

## Core screen and user flow (Phase 3B design directions cover this)

Screen S02, the Battery tool view, opened from the launcher (S16) that the menu bar item (S01) shows: current charge, effective state with the reason charging is paused, the limit control, Top up, power flow, and battery details. Flow F01: first run -> turn on Battery -> set limit -> install helper -> limit active. Directions also show the System tab (S03) to prove the tab pattern holds.

## REA and Replica findings

`docs/rea-findings.md` (triage of six public product pages; feature behavior inferred) and `replica/` (recon map, features, prompts, decisions, architecture). Complaint-driven fixes are notes in `replica/features.csv`.

## Atomic tasks

Verification commands (from the repo root):
- `V1`: `xcodegen generate && xcodebuild -scheme AppleCart -destination 'platform=macOS' build`
- `V2`: `swift test --package-path Packages/AppleCartKit`
- `S`: smoke S1-S5 (`~/.claude/skills/pre-built/references/smoke.md`) with macOS screenshots of the panel in light and dark

| ID | Task | Depends on | Acceptance criteria | Verify | Status |
| --- | --- | --- | --- | --- | --- |
| T001 | Project skeleton: `project.yml` (app target; the helper target is added by T009), `AppleCartKit` package (Core, HelperProtocol; other modules are added by the task that needs them), status item showing an icon | — | builds clean with zero warnings in new code; app launches as menu bar only (no Dock icon) | V1, V2 | done (icon not seen: no screen permission; confirm on first run) |
| T002 | Spike: charge-control backend on macOS 26/27 Apple silicon; write `docs/spikes/charge-control.md` with mechanism, sources, what works below 80%, calibration behavior, go/no-go | — | doc names a working mechanism or records NO-GO with evidence; any write to the owner's battery happens only with the owner present | doc review (Opus) | in progress (partial: see docs/spikes/charge-control.md; needs owner) |
| T003 | FeatureRegistry + SettingsStore + Settings > Features (S06): switches, off by default, unload on off | T001 | turning a tool off cancels its timers/observers (unit test with a fake tool); state survives relaunch | V2, S | done (switch tint and the open window not seen live: no screen permission; preview renders in docs/design/screenshots/build) |
| T004 | Panel shell and launcher (S16, S02 frame): non-activating panel, stays open while clicking inside, closes on outside click/Esc, header with back, title, search and overflow menu (Keep open, Settings, Collapse), launcher grid of tool tiles with shortcut hints, reorder/hide, empty states | T003 | click inside never closes it; Esc closes; tile order persists; keyboard reaches every control | V1, S | built; live click/Esc check pending (owner) |
| T005 | PermissionsService + Settings > Permissions (S07): status per permission, which tools use it, open the right System Settings pane, unused prompt | T003 | no permission requested at first launch; each request names its tool | V2, S | built; requests belong to each tool, live statuses not seen (no permission here) |
| T006 | Battery readings: details, 24 h samples, true %, power flow, energy-hungry apps (read-only, no helper) | T004 | values match `pmset -g batt` and `ioreg` within rounding; sampler stops when panel closed and no readout uses it | V2, S | built; values checked against pmset/ioreg; panel click path not seen live |
| T007 | Menu bar readouts (S01) + first run (S11, 2 screens, skippable) | T006 | readout updates within 5 s of a power change; first run skippable in one click | S | built; 5 s timing and live menu bar text not seen (no screen access) |
| T008 | Keep awake (timer, until charge level, display on) + system monitor | T004 | `pmset -g assertions` shows the assertion only while active; monitor samples only while visible | V2, S | built; pmset check passes in a test; panel click path not seen live |
| T009 | Root helper: `SMAppService.daemon`, XPC with code-signing requirement, install/repair/remove sheet (S10), `resetAll` on removal | T002 GO | unsigned client is rejected (test); helper survives relaunch; removal leaves battery charging to 100% | V1, V2, S | pending |
| T010 | Policy engine (pure) + charge limit, heat protection, sailing, top up, discharge, stop in sleep, keep after quit; paused-reason display incl. "macOS is calibrating" | T009 | unit tests cover every rule combination and the reason text; one writer to the helper | V2, S | pending |
| T011 | Calibration cycle + battery schedule (S08) with catch-up and run history | T010 | DST and missed-while-asleep cases tested | V2 | pending |
| T012 | MagSafe light modes | T009 | mode restored to system on tool off | S | pending |
| T013 | Quick toggles, volume guard, Bluetooth off in sleep | T004 | each toggle reflects real system state after change | S | partial: toggles and volume guard built; Bluetooth off in sleep NOT built (no public API, see launch-blockers); writes never run on the owner Mac |
| T014 | Fan safe mode (raise above system curve only) | T009 | helper clamps any lower value (test); fans released on off/quit | V2, S | pending |
| T015 | Flush DNS via helper | T009 | succeeds without a password prompt after helper install | S | pending |
| T016 | Uninstaller + cleanup preview (S12): bundle-ID leftovers, Trash only, Undo toast, refuse system apps | T005 | path allowlist tested; nothing outside user Library and the app is touched | V2, S | pending |
| T017 | Cache cleaner + disk usage map | T016 | same Trash-only and preview rules; scan cancellable | V2, S | pending |
| T018 | Update checks: Homebrew outdated (if installed), `softwareupdate --list` | T004 | absent Homebrew shows an empty state, not an error | S | pending |
| T019 | Clipboard history (search, pins, previews, sensitive types skipped, per-app exclusions), auto-clear, plain paste, clean links | T005 | concealed/transient/auto-generated items never stored (test); poll stops when off | V2, S | pending |
| T020 | OCR + QR region capture (S13) with toast | T005 | works offline; denied permission shows the fix | S | pending |
| T021 | Break reminders (S14), cleaning mode (S15), clear notifications | T004 | cleaning mode always shows how to exit; Reduce Motion respected | S | pending |
| T022 | Sparkle updates, launch at login, Send Debug Logs (mail draft), Delete all app data | T004 | update check hits only the appcast URL; delete removes every store | V1, S | pending |
| T023 | Energy check: idle CPU with all tools off, and with every tool on | T021 | all off < 0.1% average over 5 min (median of 5 runs, Release build) | measurement in activity.md | pending |
| T024 | Accessibility pass: VoiceOver labels, full keyboard, text size, Increase Contrast, Reduce Motion | T021 | every control labeled; no keyboard dead ends | S + VoiceOver notes | pending |
| T025 | Drafts for qualified review: privacy policy, terms, business details, third-party licenses (Sparkle) | — | drafts exist, marked NEEDS REVIEW | doc review | pending |
| T026 | Signed, notarized DMG dry run (no publish) | T022 | `spctl -a -vv` accepts; `stapler validate` passes | command output | pending |

## Safeguard coverage

| # | Safeguard | Applies | Covered by |
| --- | --- | --- | --- |
| 1 | Privacy policy | yes (local-only app, update checks reach GitHub) | T025 |
| 2 | Terms of service | yes (free app EULA) | T025 |
| 3 | Refund policy | NOT APPLICABLE: free, no payments | — |
| 4-5 | Cookie policy / banner | NOT APPLICABLE: no web surface; revisit if a website ships | — |
| 6 | Form consents | NOT APPLICABLE: no forms send data; debug logs are a user-sent mail draft | T022 |
| 7 | No unnecessary data | yes: clipboard and battery history retention, sensitive skip | T019, T006, T022 |
| 8 | Third-party SDK audit | yes: Sparkle only | T022, T025 |
| 9 | No dark patterns | yes: no nags, honest permission prompts | T005 |
| 10 | No hidden fees | yes (trivially: free) | T025 |
| 11 | No fake reviews | yes: no testimonials anywhere | T025 |
| 12 | No unsupported claims | yes: no "extends battery life" or health claims without evidence | T025, `docs/claims-evidence.md` |
| 13 | Alt text | yes, as VoiceOver labels | T024 |
| 14 | Color contrast | yes | T024 |
| 15 | Keyboard navigation | yes | T004, T024 |
| 16 | Business details | yes (publisher ASSUMED Rare Creatures LLC) | T025 |
| 17 | Children's data | NOT APPLICABLE: collects no personal data | — |
| 18 | Email unsubscribe | NOT APPLICABLE: sends no email | — |
| 19 | Asset and code licenses | yes: Sparkle MIT, SF Symbols terms | T025 |
| 20 | Data deletion | yes: Delete all app data; helper removal resets hardware | T022, T009 |

UX baseline (`docs/ux-baseline.md`, Phase 5B): undo toasts for cleanup, empty/error states per tool view, search in clipboard history, keyboard shortcuts and menu commands, dark mode, text size, Reduce Motion, 44 pt-equivalent targets where possible in a menu bar panel. Drag-to-reorder applies to tabs and sections; swipe, pull-to-refresh and pinch zoom are NOT APPLICABLE (desktop panel).

## Human review and launch blockers

`docs/launch-blockers.md`, plus: T002 go/no-go (owner present for any battery write), Developer ID certificate for notarization, public name, legal drafts review.
