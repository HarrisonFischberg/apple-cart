#!/bin/bash
# Fresh-context build loop for apple-cart. Adapted from the public ralph-loop-quickstart
# pattern (reviewed 2026-11-14): one `claude -p` session per iteration, PROMPT.md as input.
# Differences: lean cap of 6 iterations, model pinned to Sonnet, STOP file, per-iteration logs,
# no browser step (native app), no network permissions (see .claude/settings.json).
#
# Usage: ./ralph/ralph.sh <iterations 1-6>
set -u
cd "$(dirname "$0")/.."

MAX=${1:-}
if ! [[ "$MAX" =~ ^[1-6]$ ]]; then
  echo "usage: ralph/ralph.sh <iterations 1-6>   (lean cap is 6 per approved run)" >&2
  exit 2
fi
for f in PROMPT.md prd.md activity.md .claude/settings.json; do
  [ -f "$f" ] || { echo "missing $f" >&2; exit 2; }
done

mkdir -p ralph/logs
echo "Ralph: up to $MAX iterations, model claude-sonnet-5-5. Create ralph/STOP to stop after the current one."

for ((i = 1; i <= MAX; i++)); do
  if [ -e ralph/STOP ]; then echo "STOP file found, ending."; exit 0; fi
  log="ralph/logs/iteration-$(date +%Y%m%d-%H%M%S)-$i.log"
  echo "== Iteration $i of $MAX -> $log"
  claude -p "$(cat PROMPT.md)" --model claude-sonnet-5-5 --output-format text >"$log" 2>&1 || true
  tail -n 15 "$log"
  if grep -q '<promise>COMPLETE</promise>' "$log"; then
    echo "All approved tasks report complete after $i iteration(s). Review activity.md before believing it."
    exit 0
  fi
  if grep -q 'BLOCKED-NEEDS-OWNER' "$log"; then
    echo "An iteration stopped on a task that needs the owner. See activity.md."
    exit 3
  fi
  sleep 2
done
echo "Reached $MAX iterations without completion. This is not completion; see activity.md and prd.md."
exit 1
