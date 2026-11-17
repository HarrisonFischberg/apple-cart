# Compliance checklist — 20 safeguards

Statuses: PASS / FAIL / BLOCKED / NEEDS REVIEW / NOT APPLICABLE.
PASS = engineering checks passed, not legal approval. NOT APPLICABLE needs a
documented reason from actual app behavior. Missing tools or credentials are
BLOCKED, never PASS.

Item text: `~/.claude/skills/new-app/references/safeguards.md`.

| # | Safeguard | Status | Applicability / rationale | Remediation | Files / routes | Tests or checks | Evidence | Owner / open items |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Privacy policy | | | | | | | |
| 2 | Terms of service | | | | | | | |
| 3 | Refund policy | | | | | | | |
| 4 | Cookie policy | | | | | | | |
| 5 | Cookie consent banner | | | | | | | |
| 6 | Form consents | | | | | | | |
| 7 | No unnecessary data | | | | | | | |
| 8 | Third-party SDK audit | | | | | | | |
| 9 | No dark patterns | | | | | | | |
| 10 | No hidden fees | | | | | | | |
| 11 | No fake reviews | | | | | | | |
| 12 | No unsupported claims | | | | | | | |
| 13 | Alt text | | | | | | | |
| 14 | Color contrast (WCAG 2.2 AA) | | | | | | | |
| 15 | Keyboard navigation | | | | | | | |
| 16 | Business details | | | | | | | |
| 17 | Children's data | | | | | | | |
| 18 | Email unsubscribe | | | | | | | |
| 19 | Asset and code licenses | | | | | | | |
| 20 | Data deletion request | NEEDS REVIEW | Applies: local settings and history, plus hardware state set by the root helper (charger cut, fan manual mode). | Delete all app data stops every tool, awaits ChargeLimiter.shutdown (helper resetAll = charger on) and then erases. Settings > Battery > Remove calls resetAll then SMAppService unregister. Turning the Battery tool off and quitting also call resetAll. MagSafe light (2026-11-16): quit, Delete all data, Remove, Battery tool off and Indicate charge limit off call resetLED (LEDRunner); the helper stops forcing it on lease expiry, signal, XPC invalidation, sleep and start (LEDGuardTests, LEDRunnerTests). Fans (2026-11-16): Delete all data and quit await FanRunner.shutdown (helper resetFan = fans to macOS); Remove calls resetFan before unregister; turning Fan speed off calls resetFan. The helper hands the fans back on lease expiry (90 s), signal, XPC invalidation, sleep and start. The helper keeps no files; it restores the charger on lease expiry (90 s), signal, XPC invalidation, sleep and start. | App/AppDelegate.swift (deleteAllData, applicationShouldTerminate), App/HelperChargeController.swift (ChargeHelperInstaller.remove), App/BatteryTool.swift, Packages/AppleCartKit/Sources/HelperCore/AdapterGuard.swift | swift test: ChargeLimiterTests.batteryToolOffResetsAndStopsCommanding, toolTurnedOffWhileACutIsInFlightResetsAfterIt; AdapterGuardTests (lease expiry, invalidation, startup, failed restore retry); FanGuardTests and FanRunnerTests (lease expiry, sleep, start, retry cap, tool off, wake, failure) | Unit tests with fakes only (2026-11-15; review fixes added sleep refusal, wall-clock lease, maybe-live cut restore, no-CHIE path). Not yet run on the Mac: helper install, Remove, delete-all with a live cut. Release builds are ad-hoc signed, so the helper requirement (team ID) cannot be met there: the charging helper works only in a team-signed build until release signing exists. | Owner: on-device test of Remove and Delete all data while the charger is cut (see T009 steps), and while a manual fan speed is held (docs/fan-plan.md). No fan SMC write has been made on any Mac yet. |
