# Fan speed (FeatureID.fanSafeMode, shown as "Fan speed")

Built 2026-11-16 on branch feature/fan. Status: code and unit tests done; **no fan SMC write has ever been made on any Mac**.
The first live write is the owner's call, with the owner present, after reinstalling the helper (helper version 3).

## What the owner gets

Panel card "Fan control" (BETA): one row per fan ("Current 1,840 RPM", or "Fan off" when stopped), a status line from
confirmed helper state only, and System | Manual | Curve.

- System: macOS controls the fans. Choosing it is applied at once.
- Manual: Min / Medium / Max chips and a slider, 0% = the fan's minimum running speed (F0Mn), 100% = F0Mx. Nothing is
  sent until "Apply manual control".
- Curve: sensor menu (Hottest SoC, CPU, GPU, Battery) with its live temperature, a chart with draggable points, steppers
  per point, Add point (up to 6, 40-100 C, increasing), Add sensor (a second sensor: the curve follows the hotter of the
  two; if either is unreadable, macOS gets the fans), Reset to default, "Apply fan curve". 0% on the curve means "let
  macOS decide", so the fan can stay off when cool. Default curve: 55 C -> 0% (macOS), 70 C -> 30% (about 3,600 rpm),
  80 C -> 65% (about 5,100 rpm), 90 C -> 100%.
- "Resume after restart or sleep" (off by default): off means every sleep, relaunch, tool off and quit leaves the fans
  with macOS until Apply is pressed again. On re-applies the saved mode after wake or relaunch, but still only once the
  helper reports ready and a fresh temperature has been read.

Settings > Fan speed: mode (read only), Resume, the safety text and the shared helper card (Install / Repair / Remove).

## Safety rules (FanPolicy, tested in FanPolicyTests / FanRunnerTests)

- Every safety check uses the hottest single plausible sensor (max of all Tp*, Te*, Tg* readings in 5-130 C;
  sensors that are off read 0 and are left out), never an average, so one hot core cluster cannot hide behind a cooler
  mean. The CPU and GPU averages are only for display and for the CPU / GPU curve sensors. "Hottest SoC" on the curve is
  this same hottest sensor.
- No manual speed without that reading (none plausible = unknown = macOS).
- Hottest sensor at 90 C or more, or ProcessInfo thermal state serious/critical: fans to macOS at once, for 2 minutes,
  whatever sensor a curve uses.
- Heat hysteresis (decided 2026-11-16): after a heat or thermal-pressure release, Manual or Curve resumes only once the
  2 minutes have passed AND the hottest sensor is below 80 C. A Mac sitting at 85-89 C therefore stays with macOS
  instead of flapping between macOS and a manual speed every 2 minutes. Below 80 C the latch clears and normal rules apply.
- Fan response watchdog: after a manual speed starts, every fan must read within 20% of the target (and above 0) within
  15 s. If not, the fans go back to macOS, the panel says "The fan did not respond. Control returned to macOS." and
  nothing manual is tried again until the owner presses Apply.
- Another app: if the helper reports manual mode we did not set, it is handed back to macOS once; if it comes back, the
  panel says "Another app is controlling the fans." and Apple Cart leaves it alone until the owner presses Apply.
- Quit and Delete all data always hand the fans back. Quit keeps the applied mode only when Resume is on (the next launch
  re-applies it once the helper is ready and a fresh temperature is known); turning the tool off or choosing System
  forgets it.
- Never below the fan's minimum running speed (app maps 0% to F0Mn; the helper clamps again into [F*Mn, F*Mx]).
- Smoothing: a new target is taken when it differs by more than 100 rpm or 10 s after the last change; switching
  between macOS and a manual speed also waits the 10 s (safety releases do not wait).
- Runner: evaluates every 5 s, renews the helper lease every 30 s (lease 90 s), hands the fans back on any failure,
  tool off, quit, Delete all data, wake, unknown temperature and an unknown manual state reported by the helper.

## SMC keys and the write sequence (HelperCore/FanGuard.swift, SMC.swift)

Read-only probe on this Mac (MacBook Pro M5, Mac17,2, macOS 27.2, one fan):

| Key | Type (from the SMC) | Value seen | Use |
| --- | --- | --- | --- |
| FNum | ui8 | 1 | fan count |
| F0Ac | flt | 0 at idle (fan stopped) | actual rpm (read) |
| F0Mn | flt | bytes 00 d0 10 45 = 2317 rpm | minimum running speed (read) |
| F0Mx | flt | bytes 00 b0 cc 45 = 6550 rpm | maximum (read) |
| F0Tg | flt, attrs 0xd4 (writable) | | target rpm (write) |
| F0md | ui8, attrs 0xd0 (writable) | 0 | mode: 0 = macOS, 1 = manual (write) |
| Ftst | absent on this Mac | | unlock, used only where present |

Manual (setFan): read FNum and, per fan, the mode key (F{i}md, or F{i}Md on older SMCs), F{i}Tg, F{i}Mn, F{i}Mx, and
check each key's type and size (ui8/1, flt/4) before any write; any mismatch or missing key = "unsupported", nothing
written. Arm the lease timer first, then: Ftst = 1 (only if the key exists as ui8), F{i}Tg = clamped rpm as a
little-endian float for each fan (target first, so a fan is never in manual mode at a stale target), then F{i}md = 1
for each fan, then read both back. A mode that is not 1, or a target more than max(25 rpm, 1%) from what was written
(or unreadable/NaN), restores (mode 0, verified) and returns notApplied. Any write error part way restores too.

Restore (lease, sleep, signal, disconnect, resetFan, start): F{i}md = 0 for each fan, then Ftst = 0 if present, then read
each mode back. At helper start and whenever nothing of ours can be live, it first reads the modes and writes nothing if
they are already 0. A failed restore retries at 5, 15, 60 s and then every 60 s (capped while manual may be live), like
the charger. Every write and its result is logged (unified log, subsystem app.rarecreatures.applecart.helper, category fan).

Whitelist (FanWhitelist): writes only to F[0-9]md / F[0-9]Md (0 or 1), F[0-9]Tg (finite float 1-10000) and Ftst (0 or 1);
reads only those plus FNum, F*Ac, F*Mn, F*Mx. The charger whitelist is unchanged and separate.

### Verified vs not verified

- Verified (read-only, this Mac): the key names, types, sizes, attributes and the min/max values above.
- Verified (unit tests with a fake SMC): sequence order, type refusal, clamping, lease, retries, sleep, start, invalidation.
- **Not verified**: that writing F0md = 1 and F0Tg actually changes the fan on macOS 27 / Apple M5, that no unlock key is
  needed here, that writing F0md = 0 hands control back immediately, and how quickly F0Ac follows. Public reports
  for earlier Apple silicon say F*md = 1 then F*Tg works and some versions also need Ftst = 1; that is the basis, not proof.

## Helper version

HelperIdentity.version is 3. A version 2 helper still drives the charge limit (status/setAdapter/resetAll are
unchanged, so the charger keeps working); the Fan speed tool shows "out of date" and the Settings helper card offers
Repair. Fan calls are never sent to a version 2 helper.

## Owner's first live test (with the owner present)

1. Build and run the team-signed app from this branch. Settings > Battery (or Fan speed) > helper card > Remove, then
   Install and approve Apple Cart in System Settings > General > Login Items. The card should read "Installed and working".
2. Open Console, filter subsystem `app.rarecreatures.applecart.helper`, category `fan`. At helper start it should log
   the fan layout and write nothing (fan is in mode 0).
3. Turn on Fan speed, wait for an idle fan ("Fan off"). Manual > Min > Apply manual control. Expect the log
   "write F0Tg ...: ok", "write F0md [1]: ok", "reads back mode [1], target 2317.0", and the panel "Current ~2,300 RPM"
   within a few seconds. If the fan does not follow within 15 s the app hands back by itself and says so.
4. After about 30 s press Return to System. Expect "write F0md [0]: ok" and the fan to spin down to "Fan off".
5. If step 3 logs ok but the fan stays at 0 rpm, the writes do not take effect on this Mac: press Return to System and
   stop there (report notApplied/log lines). If anything looks wrong, quit Apple Cart (fans go back within the call) or
   wait 90 s for the lease, or Remove the helper.
6. Optional: Apply again, then sleep the Mac; on wake the panel should show System and the log "fans to system (system will sleep)".
