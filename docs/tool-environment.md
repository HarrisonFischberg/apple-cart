# Tool environment

Verified: 2026-11-14. Mode: lean. Phase 0-1 model: Fable 5.2 (Phase 2 onward needs Opus per `handoff.md`).

## Platform profile

macOS native only (menu bar app). Runtime evidence: `xcodebuild`, XCUITest,
VoiceOver, keyboard and menu-bar checks. No web surface, so
`web-quality-audit`, Lighthouse, `seo`, and Core Web Vitals are NOT APPLICABLE
(reason: no web surface). Toolchain: Xcode 27.2 (27B52), Swift 6.4.2,
Node v24.22.0, Python 3.9.6.

## Placeholders (clean-room.md)

- `{{APP_NAME}}`: Apple Cart (working title only; cannot be the public name, see launch-blockers #1). Slug `apple-cart`.
- `{{APP_DIR}}`: `/Users/harrison/projects/apple-cart`
- `{{LAB_DIR}}`: `~/apple-cart-lab`
- `{{SOURCES}}`: five live Mac apps, public pages only. For each: catalogue every feature and option; the owner picks a la carte at the comparison stop.
  - https://sindresorhus.com/supercharge
  - https://vorssaint.com (also the model for the overall menu bar form)
  - https://getdroppy.app
  - https://macapp.supply/app/vehla
  - https://habitatformac.com
- `{{AVOID_TERMS}}`: derived from the sources' names, domains, and authors; confirmed in Phase 2B.
- `{{UI_OPTION_COUNT}}`: 3 (lean)

| Tool | Available | Version | How verified |
| --- | --- | --- | --- |
| Replica | Yes | replica-skill 1.0.0 | `installed_plugins.json`; `replica-skill:replica-*` in session skill list |
| REA (MCP tools answer, not just skill installed) | NEEDS REVIEW | n/a | `rea` MCP server connected and tool schemas load this session; no analysis call made yet. First real call is Phase 2. |
| Claude Code `/goal` | NEEDS REVIEW | n/a | Not exercised in Phase 0-1; verify before Phase 4. |
| Ralph fresh-context shell loop | BLOCKED | n/a | Only the `ralph-loop` plugin 1.0.1 (same-context) is installed; the quickstart repo is not cloned. Clone and review before Phase 4. |
| Impeccable (`/impeccable` listed in session) | Yes | version not read | `impeccable` in session skill list; installed at `~/projects/.claude/skills/impeccable`; no per-project install or restart needed. |

Impeccable hooks: `SessionStart`, `PostToolUse` (`Edit|Write`), `Stop` live in
`~/projects/.claude/settings.local.json` (3 references found). Kept.
For this native-only target, Impeccable's browser-preview commands are NOT
APPLICABLE; design evidence is macOS screenshots.

GitHub: `gh` logged in (two accounts in keyring; HarrisonFischberg is the one used for repos).

## Section F — design, accessibility, quality layer

| Skill | Available | Version / source | How verified |
| --- | --- | --- | --- |
| ui-ux-pro-max (design decisions) | Yes | `~/.claude/skills/ui-ux-pro-max` | Folder present and in skill list; not run yet |
| fixing-accessibility (edit-time a11y) | Yes, limited use | `~/.claude/skills/fixing-accessibility` | Present; web-UI tool, native a11y uses `ios-accessibility` guidance and VoiceOver checks |
| web-quality-audit + siblings (evidence) | NOT APPLICABLE | `~/.claude/skills/web-quality-audit` | Present, but no web surface |

Missing tool or credential = BLOCKED, never PASS.
