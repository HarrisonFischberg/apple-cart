# Spike T002: charge control on macOS 26 and 27 (Apple silicon)

Date: 2026-11-14, updated 2026-11-15. Status: **PARTIAL.** Adapter cut is a confirmed GO on this Mac (macOS 27.2.1, M5). Charge limit below 80%, sleep, reboot and helper-crash behavior are not tested yet.

## This Mac (read-only probes; nothing was written)

- MacBook Pro `Mac17,2`, Apple M5, macOS 27.2.1 (build 26B131), system firmware 20457.41.3, 98 battery cycles.
- Right now: 80%, AC attached, not charging, with a non-zero not-charging reason code in the battery registry. Something is holding the charge at 80%.
- **Another limiter is installed here:** AlDente Pro's privileged helper is installed and its app is present, and Vorssaint is running. The 80% hold is probably theirs (an Apple native limit is the other possibility; I did not read that setting). Evidence, not proof: a third-party tool appears to hold a limit on this exact Mac and OS.
- Consequence: any write test would fight AlDente's helper. It has to be quit and its limit reset first, or the result means nothing.

## What the public sources say (second-hand; not tested here)

| Capability | Mechanism reported | Needs | macOS 26 | macOS 27 |
| --- | --- | --- | --- | --- |
| Limit charge % | Apple's own Charge Limit in System Settings (80-100%, UI only, no public API found); third-party tools write charge keys through a root daemon, or keep Apple's native target in sync | root daemon | native limit from 26.4; third-party SMC route works but one report says later 26.x security updates gated some keys | reports that direct charge keys became unavailable in later betas; the adapter-cut route still works, awake only; Apple's limit still exists |
| Pause charging | same keys; on 27 only cutting the adapter | root daemon | works | adapter cut only |
| Discharge while plugged in | disable the adapter so the battery carries the load | root daemon | works | adapter route reported not gated; effect on calibration unclear |
| MagSafe LED | SMC write on MagSafe Macs | root daemon | described as working | unknown |
| Raise fan speed | SMC fan keys with a helper; some M3/M4 models block overrides | root helper | vendor claims work, model-dependent | no source found |

Sources: Apple's battery support page (support.apple.com/102338); the batt project's README and issue and pull request threads 152 and 154 (github.com/charlie0129/batt); Battery-Toolkit (github.com/mhaeuser/Battery-Toolkit, archived upstream per one blog); AlDente's public feature and FAQ pages (apphousekitchen.com); a third-party blog on macOS 27 charge-limit breakage (macos-tahoe.com). Several 27 claims come from that blog and issue threads, not Apple, and mostly describe betas and early releases. This Mac runs 27.2.1, so they may be out of date. A privileged helper installed with `SMAppService` and checked XPC callers is the normal pattern; nothing found says Apple blocks it.

Also seen in earlier public reports: while macOS runs its battery gauging (calibration) routine it ignores limits, including its own; reporters had third-party replacement batteries.

## Recommendation (to be confirmed by tests)

- **Charge limit:** conditional go. Baseline is Apple's native Charge Limit (80-100%) shown read-only in our panel with a link to Settings; a custom range below 80% or hold-in-sleep behavior needs a third-party route and is unproven on 27.
- **Pause charging and discharge:** conditional go via the adapter route, only if the write probe passes on this Mac.
- **MagSafe LED:** no-go until a write probe passes. No evidence on 27.
- **Fan safe mode:** conditional, per model; no-go if the probe shows the hardware refuses overrides.
- If the write probes fail, the read-only battery tools (details, history, power flow, energy-hungry apps, true percentage) still ship and the control tools are marked BLOCKED, as planned in the blueprint.

## Plan, in order

1. Read-only (can be done now, no owner needed): enumerate SMC keys and their sizes and privilege errors with an unprivileged user-space probe (no writes). The probe is a small Swift tool added under `design/`-free `spikes/` once approved.
2. **Owner decision needed:** quit AlDente and reset its limit to 100%, and note whether Apple's own Charge Limit is on in System Settings. Without this, step 3 is meaningless.
3. Writes, with the owner at the Mac and a restore on a timer: adapter cut for 2 minutes then restore; confirm the Mac keeps running on battery and charging resumes by itself. LED and fan writes only after step 3 passes, and only if the owner agrees to each.
4. Sleep, reboot and a helper-crash test (restore must happen on its own) before T010 starts.

## Not verified

AlDente's and Battery-Toolkit's own issue trackers; exact SMC key names beyond what the batt threads mention; whether `pmset` or a public power API has any write option; the private entitlement one reporter suspects; fan control on 27; anything about notarizing a daemon; Apple's 27 release notes.


## Results 2026-11-15 (owner at the Mac, AlDente quit, Apple Charge Limit = 100%)

1. **AlDente was the 80% hold.** After quitting its app (its helper stays installed but idle), charging resumed within a minute. `pmset` went from "not charging" to "charging". Vorssaint (fan helper) was left running; it did not interfere.
2. **Read-only key list** (`spikes/smc-probe`, no root, no writes; output in `smc-keys-readonly.txt`): 2,906 SMC keys. Absent here: `CH0B`, `CH0C`, `CHTE` (the keys older tools use). Present and flagged writable: `CHIE` (1 byte, adapter disable), plus many other `CH*`/`AC*`/`BC*` keys not yet understood.
3. **Adapter cut write: PASS.** `sudo adapter-cut-test.sh 120` wrote `CHIE=08`: no error, readback 08. Within 10 s macOS reported "Battery Power, discharging" with the charger still plugged in; stayed that way for 120 s at 82%, Mac stayed up. Log: `adapter-cut-log.txt`.
4. **Restore: key PASS, charging resume NOT automatic within about 3 minutes.** Writing `CHIE=00` read back 00 and macOS showed "AC Power" again, but charging stayed off ("not charging", reason code 4096) until the owner unplugged and replugged the charger; then charging resumed (reason 0). I cannot tell whether the replug or just more time fixed it. **Design consequence for T009/T010:** after restoring, the helper must verify charging actually resumes and keep a visible warning if it does not; never assume the key write alone is enough.

## Updated recommendation

- **Pause charging and discharge via the adapter route:** GO on this Mac and OS, with the restore caveat above.
- **Charge limit:** still conditional. A limit below 80% can be built as hold-by-cutting-the-adapter-and-restoring, awake only. Apple's native limit (80-100%) stays the baseline.
- **MagSafe LED, fan safe mode:** unchanged, no write probe run yet.
- **Still to test before T010:** whether the restore resumes by itself given more time (wait 10 min, no replug); sleep with the adapter cut; reboot with the adapter cut; helper killed mid-cut.

### Second restore test 2026-11-15 14:56 (no replug; `resume-watch.txt`, `adapter-cut-log.txt`)

Same 120 s cut, this time at 97%. After `CHIE=00`, macOS said "not charging" for about 30 s and then "charging" at 45 s, with no replug. Run 1 (at 82%) did not resume for 3+ minutes. So auto-resume works sometimes and not others; the battery level, a macOS hold, or timing may matter and is not understood. Keep the rule: after any restore the helper checks that charging resumed, retries, and shows a warning if it does not. Not enough data for a number (2 runs).

## Holding without going on battery (2026-11-18)

**Owner report:** at the 80% limit the screen dims for a moment. **Cause:** every hold was a charger cut (`CHIE=08`). macOS then reports "Battery Power" with the charger still plugged in (result 3 above), so "Slightly dim the display on battery" dims the screen, and the Mac drains from the battery while it "holds". On this Mac's firmware the charge-inhibit keys that let other tools pause charging while staying on AC (`CH0B`, `CH0C`, `CHTE`) do not exist (result 2), and `CHIE` is the only writable charger key, so the SMC alone cannot do it.

**Change:** limits of 80% and up are now held by macOS's own charge limit (System Settings > Battery > Charging > Charge Limit, 80-100%), set from the app through PowerUI's `PowerUISmartChargeClient` (`setMCLLimit:error:`, `enableMCL:`, `disableMCL:`, `isMCLCurrentlyEnabled:`, `isMCLSupported`) and read back with `pmset -g battlimit` (`chargeSocLimitReason = manualChargeLimit`, `chargeSocLimitSoc`). The firmware stops charging and the Mac keeps running from the charger, as at a full charge. No root and no helper are needed for this route.

- **Sailing** on this route: once the battery reaches the limit, macOS's limit follows the battery down (set to the current level), so plugging back in does not top it up; at the floor it goes back to the limit and charging resumes. macOS will not take a limit below 80%, so the floor stops at 80% ("Will sail to 80%").
- **Still a charger cut (runs on battery):** limits below 80%, Automatic Discharge / Discharge (asked for), heat protection pauses, and Macs where the macOS limit is missing or ignores the write (three failed read-backs in a row switch back to cuts for the session). For a cut hold the panel and Settings show the workaround: turn off "Slightly dim the display on battery" in System Settings > Battery > Options, with a button to open Battery settings.
- **Giving it back:** the person's own macOS limit is saved (UserDefaults `chargeNativeLimitSnapshot`) before the first change and restored when the limit is turned off, set below 80%, the Battery tool is turned off, or the app quits.
- **Percent used:** macOS's limit works on macOS's own percentage, not the app's measured figure, so the shown percent can sit a point or so off the limit while held.

**Sources (second-hand, not Apple):** actuallymentor/battery PR 480 (the `PowerUISmartChargeClient` calls, 80-100 range, crash below 80), cshariq/Sapphire issue 203 (same `CHIE` symptom on an M5 / macOS 27, `pmset -g battlimit` showing `manualChargeLimit` with the Mac on AC), actuallymentor/battery PR 478 (only `CHIE` responds on macOS 27; cutting the adapter runs the Mac on battery). Reports also say AlDente 1.39 uses the macOS limit this way, which matches the 80% "AC attached, not charging" hold seen on this Mac on 2026-11-14.

**Not verified yet (needs the owner's Mac):** that the selectors exist with these signatures on macOS 27.2.1; that the hold stays on AC power with no dim; how far macOS lets the charge drift below its limit before topping up; behavior through sleep and macOS's calibration (reported to override limits).
