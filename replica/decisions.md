# Reference and parity decisions

Sources are named only as Source A-F. All wording here is original.

## Intentional differences from the sources (safer design, not parity defects)

- Fan control can only raise fan speed above the system curve, never lower it (owner choice at final review; prevents overheating).
- Cleaner and uninstaller always preview and move to Trash; no permanent delete.
- Clipboard history never stores concealed or password-manager items, even though one source stores everything.
- Every tool is free with no caps, trials or paid tiers.
- Permissions are asked per tool at enable time; nothing is requested at first launch.
- The privileged helper accepts commands only from the signed app and is removed (battery reset to 100%) when the owner removes the app.

## Owner final review (2026-11-14)

- 34 features picked; added battery schedule.
- Dropped the mouse jiggler (keep awake covers it).
- Moved the connection map and dictation to Later.
- Distribution: notarized direct download (20 picks cannot run in the App Store sandbox).
