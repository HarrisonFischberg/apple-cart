# MagSafe LED write probe: plan (2026-11-16, not run)

## Question
Can Apple Cart set the MagSafe light (green at limit, orange while charging) on this Mac (M5, macOS 27.2), and does it stay set?

## What we know
- `ACLC` is a 1-byte `ui8` key, attrs `0xd4`, read OK unprivileged (`smc-keys-readonly.txt`). Seen values: `03` = green, `04` = orange. Nothing else is known, so the probe only ever writes 3 or 4.
- The key is flagged writable (like `CHIE`, which did accept writes as root).
- Unknown: whether the SMC accepts the write, whether macOS rewrites it on its own (charge state change, sleep, plug/unplug), and what "give it back to macOS" means for this key.

## Risk
Low. The light is cosmetic and does not touch charging. Worst case: the light shows the wrong colour until macOS rewrites it, a charger replug, or a reboot. The probe restores the original value on exit and on a timer.

## Probe (a throwaway spike, `spikes/led-probe`, run with `sudo`, owner at the Mac)
Reuses `HelperCore/SMC.swift`. Writes `ACLC` only. Traps SIGINT/SIGTERM and always writes the original value back; a 90 s timer does it too.

1. **Baseline.** Charger plugged in, limit held below the battery percent (light reads 4 orange today while held). Read `ACLC` and note what the light shows.
2. **Write 3.** Write `03`, then read back at 0, 0.5, 2, 5, 10, 30 s. The owner says what the light shows at about 5 s and 30 s.
3. **Restore.** Write the original back. Read back and confirm the light follows.
4. **Reverse.** From a green light (limit lifted or Top Up at the limit), write `04` and repeat steps 2 and 3.
5. **Stickiness (only if 2 or 4 passed).** With the value forced, do each one at a time: unplug and replug the charger; sleep and wake; let the charge state change (pause to charging). Note whether macOS overwrites the value and how fast.

## Pass / fail
- **Pass:** the write reads back, the light changes, and it holds for at least 30 s and through a charge-state change, or a rewrite by macOS is slow enough that the helper's 30 s renewal can keep it right.
- **Fail:** the write is refused, reads back unchanged, or macOS overwrites it within seconds.

## If it passes
Build it like the charger and fan guards: helper command with a lease, `ACLC` added to the SMC whitelist, protocol bump, restore on lease expiry, sleep, SIGTERM and helper start. Rules to follow are in `docs/battery-parity.md` (green at limit and while sailing, orange for sleep, app-closed and heat pauses). Settings: Indicate Charge Limit, Blink Orange during Discharge (blink needs its own timing test), LED Always Off / Off During Sleep (needs values we do not know yet; separate probe, only with the owner's agreement).

## If it fails
Keep the light read-only and explained. Mark the parity row BLOCKED with this probe's log as evidence.

## Owner steps (one result at a time)
1. Confirm the Mac is on the charger and the limit is below the battery percent.
2. Run the probe command I give you in Terminal, then tell me the light colour at the prompts.

## Results (2026-11-16, owner at the Mac, probe d4e1aeb)
- Run 1 (orange to green, 35 s, no events): write accepted (`smc=0`), read back `03` from 0.5 s on, held 35 s, light green. Restore wrote `04`; the key read `04` afterwards. A read right after a write shows the old value (about 0.5 s lag), so any read-back needs a short wait.
- Run 2 (green forced 50 s, charger unplugged about 3 s and replugged at about 10 s): `03` at 10 s, `04` by 20 s, and it stayed `04`. The owner saw the light stay orange after the replug. macOS rewrites `ACLC` itself on an adapter event.
- Verdict: **conditional pass.** The write works and holds while nothing changes, but macOS overwrites it on a plug/unplug. Not yet tested: sleep and wake, and a charge-state change (pause to charging).
- Design consequence: the helper cannot set it once. It has to read `ACLC` every 1-2 s while a colour is wanted and write it again when macOS changes it, so the light can flash the wrong colour for up to that interval after an event. Restore on lease expiry, sleep, SIGTERM and helper start, as with the charger and fan guards.
