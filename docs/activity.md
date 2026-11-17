## 2026-11-16: MagSafe LED control (Indicate charge limit)
- Helper v4: LEDGuard (ACLC 3/4 only, lease, 1 s correction tick, restore on every exit), protocol setLED/resetLED/ledStatus; v2/v3 helpers still drive charge and fans. App: LEDPolicy + LEDRunner, Settings > Battery "Indicate charge limit" (off by default). Tests 258+70+5 pass; app target builds.
- NOT installed: helper v4 needs Settings > Remove, then Install, approve in Login Items, with the owner at the Mac. App-side behaviour untried on hardware; sleep/wake and charge-state changes untested for ACLC.


## 2026-11-16 overnight: audit round
- Ponytail audit (docs/audit-2026-11-16.md): 17 findings. Fixed 2-9, 12-16 and the minHold floor guard of 1 (commits d39abdf..e682fc8), plus a reviewer follow-up: fan watchdog window extension capped at 2x responseWindow, CHIE read-back waits 150 ms. Tests 249+52+5 pass; app target builds.
- Left for the owner: 1 (0-100 slider kept by request), 10, 11, 17.
- NOT installed: the helper changed (AdapterGuard, HelperService), so it needs Settings > Remove, Install, approve in Login Items with the owner at the Mac; relaunching the app overnight would also end the owner's keep-awake session. The CHIE read-back is unverified on hardware: if cuts report "Helper error notApplied", revert 61da002's read-back.
