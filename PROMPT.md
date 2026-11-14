# Per-iteration instructions (apple-cart)

You are one fresh session in a bounded build loop. Work on exactly ONE task, then stop.

1. Read `CLAUDE.md`, `prd.md`, `activity.md`, `docs/launch-blockers.md`, `docs/blueprint.md`, `DESIGN.md`.
2. Pick the first task in `prd.md` whose Status is `pending` and whose dependencies are all `done`.
   Never pick these (they need the owner at the Mac, an admin prompt, or a real battery write):
   T002, T009, T012, T014, T015, T026. If the next ready task is one of these, print
   `BLOCKED-NEEDS-OWNER` and the task id, record it in `activity.md`, and stop.
3. Bounded goal for this iteration (at most 3 attempts to get the checks green): write the task's
   acceptance criteria and its verification command at the top of your `activity.md` entry. Done means
   that command's real output passes. If it does not pass after 3 attempts, mark the task `abandoned`
   in `prd.md` with the reason and stop. Do not weaken a test or a check to make it pass.
4. Implement only that task, matching `docs/blueprint.md`. If the blueprint is wrong or incomplete,
   stop, write the problem in `activity.md`, and do not redesign it yourself.
5. Run `V1` and `V2` from `prd.md` (xcodegen generate, xcodebuild with `-derivedDataPath .build/DerivedData`,
   swift test). New code must build with zero warnings.
6. Any UI task: follow `DESIGN.md` tokens (light and dark), native controls with the concept's tint,
   keyboard access and accessibility labels.
7. Never run `pmset`, SMC tools, sudo, or anything that writes to the battery, fans or system settings.
8. Update the task's Status in `prd.md` (`done` or `abandoned`), append a dated entry to `activity.md`
   (what changed, commands run, results, issues), and make one commit for this task only.
   Never push, never change git remotes, never run `git init`.

Output `<promise>COMPLETE</promise>` only when every task in `prd.md` is `done` with its checks passing.
