# Ralph loop (apple-cart)

Fresh-context loop adapted from the public ralph-loop-quickstart pattern (reviewed 2026-11-14; its
browser step, wildcard network permissions and `npm` allowances were dropped).

- Run: `./ralph/ralph.sh 3` (1-6 iterations; lean cap is 6 per approved run). One `claude -p` session
  per iteration, model pinned to `claude-sonnet-5-5`, logs in `ralph/logs/` (gitignored).
- Stop early: `touch ralph/STOP`.
- Permissions: `.claude/settings.json` (builds, tests and local git commits only; no push, no network,
  no `sudo`, no `pmset`).
- Tasks that need the owner (T002, T009, T012, T014, T015, T026) are never picked; the loop stops with
  `BLOCKED-NEEDS-OWNER`.
- Limits: 3 attempts per task instead of `/goal` turns. `/goal` is not available in this session
  (see `docs/tool-environment.md`); the bounded condition is written into `PROMPT.md` instead.
- Reaching the iteration limit is not completion. Stop after one iteration with no progress and
  escalate to Opus.
- Not yet run: the first run will show whether the sandbox allows `xcodebuild`; if it does not, the
  fix is to widen `sandbox` settings deliberately, never to disable it silently.
