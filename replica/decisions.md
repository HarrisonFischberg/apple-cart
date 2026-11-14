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

## Display structure adopted from the reference (owner request, 2026-11-14)

The owner asked for the panel to closely follow the display of Source A. Adopted: the structure and interaction model only (launcher grid of tool tiles with shortcut hints and search; header with title, search and overflow menu; tool views made of stat tiles with a large value and thin bar; wide and narrow tile rhythm). Not adopted: its name, logo, icons, copy, imagery, or notch-island placement. Icons are SF Symbols; all wording is original; the panel hangs from the status item. This replaced the four-tab panel in `docs/blueprint.md`, `prd.md` and this folder's recon, features and prompts.

## Design direction (approved 2026-11-14)

C4 Tiles. C1 Tape, C2 Rams and C3 Course were built and rejected; their code stays on local branches `ui-1`, `ui-2`, `ui-3` and their screenshots in `docs/design/screenshots/`. Ideas worth carrying later: C3's numbered event legend for the battery history, C1's tape-style limit slider.
