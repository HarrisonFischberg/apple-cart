## 2026-11-16: MagSafe LED control (Indicate charge limit)
- Helper v4: LEDGuard (ACLC 3/4 only, lease, 1 s correction tick, restore on every exit), protocol setLED/resetLED/ledStatus; v2/v3 helpers still drive charge and fans. App: LEDPolicy + LEDRunner, Settings > Battery "Indicate charge limit" (off by default). Tests 258+70+5 pass; app target builds.
- NOT installed: helper v4 needs Settings > Remove, then Install, approve in Login Items, with the owner at the Mac. App-side behaviour untried on hardware; sleep/wake and charge-state changes untested for ACLC.


## 2026-11-16 overnight: audit round
- Ponytail audit (docs/audit-2026-11-16.md): 17 findings. Fixed 2-9, 12-16 and the minHold floor guard of 1 (commits d39abdf..e682fc8), plus a reviewer follow-up: fan watchdog window extension capped at 2x responseWindow, CHIE read-back waits 150 ms. Tests 249+52+5 pass; app target builds.
- Left for the owner: 1 (0-100 slider kept by request), 10, 11, 17.
- NOT installed: the helper changed (AdapterGuard, HelperService), so it needs Settings > Remove, Install, approve in Login Items with the owner at the Mac; relaunching the app overnight would also end the owner's keep-awake session. The CHIE read-back is unverified on hardware: if cuts report "Helper error notApplied", revert 61da002's read-back.

## 2026-11-18: release prep (docs only)
- Added README.md, docs/release-checklist.md (helper version bump rule for audit 11, signing, notarization, open blockers), and T025 drafts in docs/legal/ (privacy policy, terms, third-party notices with the Sparkle 2.10.1 license), all marked NEEDS REVIEW.
- prd.md statuses refreshed for T009, T010, T012, T014, T025 from the 11-15/11-16 logs. Data inventory: table gap fixed, update-check row moved into the table and Homebrew added.
- No code changed; nothing built or run (cloud session, no Xcode).

## 2026-11-19: helper hardening (audit 10 and 17)
- Audit 10: in Release builds both ends of the XPC connection also require Developer ID (leaf 1.2.840.113635.100.6.1.13 and intermediate 1.2.840.113635.100.6.2.6). Debug requirement strings are unchanged, so the installed Debug helper behaves exactly as before and needs no reinstall.
- Audit 17: the client's timeout/resume-once race and the reply-code mapping moved from App/HelperChargeController.swift into Core/HelperCall.swift with tests (CoreTests now also depends on HelperProtocol to pin the codes). CI now type-checks HelperChargeController.swift and Helper/main.swift in both Debug and Release.
- HelperIdentity.version not bumped: the Debug helper is unchanged in behavior; the Release change ships with the first Developer ID build. Not covered: stop/start ordering between the battery and fan tools (still App-only).
