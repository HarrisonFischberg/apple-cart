#!/bin/bash
# T002: after adapter-cut-test.sh finishes (no replug), log charging state every 15 s for up to 10 min.
LOG="$(cd "$(dirname "$0")/../.." && pwd)/docs/spikes/adapter-cut-log.txt"
OUT="$(cd "$(dirname "$0")/../.." && pwd)/docs/spikes/resume-watch.txt"
rm -f "$OUT"
until grep -q "after restore" "$LOG" 2>/dev/null; do sleep 2; done
start=$(date +%s)
while [ $(( $(date +%s) - start )) -lt 600 ]; do
  line="$(( $(date +%s) - start ))s $(pmset -g batt | tail -1 | tr '\t' ' ')"
  echo "$line" >> "$OUT"
  case "$line" in *"; charging"*) echo "RESUMED" >> "$OUT"; exit 0;; esac
  sleep 15
done
echo "NOT RESUMED after 600s" >> "$OUT"
