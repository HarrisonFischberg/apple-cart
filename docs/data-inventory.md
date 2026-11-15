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
| Hardware state applied by the root helper | charge control, fans, LED | helper commands | helper memory only; no files | until reset | removal runs resetAll (battery to 100%, fans to system) |

No analytics, crash reporting, advertising or AI providers.

| macOS update service (via `softwareupdate --list`) | update check, only when the user presses Check now | Mac contacts Apple as macOS does; the app sends nothing itself | no |
