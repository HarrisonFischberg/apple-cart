
## 2026-11-16 overnight: audit round
- Ponytail audit (docs/audit-2026-11-16.md): 17 findings. Fixed 2-9, 12-16 and the minHold floor guard of 1 (commits d39abdf..e682fc8), plus a reviewer follow-up: fan watchdog window extension capped at 2x responseWindow, CHIE read-back waits 150 ms. Tests 249+52+5 pass; app target builds.
- Left for the owner: 1 (0-100 slider kept by request), 10, 11, 17.
- NOT installed: the helper changed (AdapterGuard, HelperService), so it needs Settings > Remove, Install, approve in Login Items with the owner at the Mac; relaunching the app overnight would also end the owner's keep-awake session. The CHIE read-back is unverified on hardware: if cuts report "Helper error notApplied", revert 61da002's read-back.
