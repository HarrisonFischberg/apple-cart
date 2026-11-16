# Data inventory

Planned (blueprint 2026-11-14). Everything stays on the Mac unless a row says otherwise.

| Data | Purpose | Collection point | Recipient / storage | Retention | Deletion |
| --- | --- | --- | --- | --- | --- |
| Tool settings and battery policy | remember choices | Settings, panel | UserDefaults (local) | until changed | Delete all app data; removing the app |
| Battery samples (percent, temperature, watts, cycles) | 24 h history graphs | IOKit readings | Application Support store (local) | 24 hours rolling | automatic; Delete all app data |
| Schedule tasks and run history | battery schedule | Settings > Battery | local store | tasks until deleted; runs 30 days | delete task; Delete all app data |
| Clipboard items (text, links, images, colors) | clipboard history | system pasteboard, only while the tool is on | local store; images as local files | 7 days default (owner-set), pinned kept | per item, clear all, turning the tool off offers to clear, Delete all app data |
| Sensitive pasteboard items (concealed, transient, auto-generated, excluded apps) | none | — | never stored | — | — |
| App names and leftover file paths | uninstaller and cleaner preview | file system scan on request | memory only during the scan | not kept | — |
| Update check request | app updates (Sparkle) | automatic or manual check | GitHub Releases receives IP address and user agent with app version | per GitHub's policies | turn off automatic checks |
| Debug logs | support | user taps Send Debug Logs | Mail draft the user reviews and sends to the support address | per the user's mailbox and support inbox | user-controlled |
| Hardware state applied by the root helper | charge control (fans, LED later) | XPC commands from the signed app only (code-signing requirement: bundle ID + team ID) | root helper memory only (adapter cut + lease timer); no files, no network | at most the 90 s lease, renewed every 30 s while a limit is held | lease expiry, signal, app disconnect, sleep and helper start all put the charger back on; tool off, quit, Delete all app data and Remove call resetAll |
| Charge control settings (limit, below-80 toggle, Top Up, sailing difference, automatic discharge, heat max in Celsius) | charge limit | Settings > Battery, panel | UserDefaults (local); the helper only ever receives "charger on" or "charger off for N seconds" | until changed | Delete all app data |

No analytics, crash reporting, advertising or AI providers.

Root helper (T009, 2026-11-15): `AppleCartHelper`, a launchd daemon embedded in the app and registered with `SMAppService.daemon`. Local only: it talks to the Apple Cart app over XPC and to the Mac's SMC, never to the network, and it stores nothing. New data flow, no new vendor.

| macOS update service (via `softwareupdate --list`) | update check, only when the user presses Check now | Mac contacts Apple as macOS does; the app sends nothing itself | no |
