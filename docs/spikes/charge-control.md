# Spike T002: charge control on macOS 26 and 27 (Apple silicon)

Date: 2026-11-14. Status: **PARTIAL, no go/no-go yet.** Public research and read-only probes are done. Every write test needs the owner at the Mac, and one blocker below must be cleared first.

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
