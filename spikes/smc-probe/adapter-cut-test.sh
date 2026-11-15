#!/bin/bash
# T002 step 3. Run with sudo, at the Mac, charger plugged in. Cuts the adapter for N seconds
# (default 120) then restores it, even on Ctrl-C. Logs pmset every 10 s.
PROBE="$(cd "$(dirname "$0")/../.." && pwd)/.build/smc-probe"
N="${1:-120}"; LOG="$(cd "$(dirname "$0")/../.." && pwd)/docs/spikes/adapter-cut-log.txt"
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
restore() { "$PROBE" --set-chie 00 | tee -a "$LOG"; }
trap 'restore; exit 130' INT TERM HUP
{ echo "== $(date) before"; pmset -g batt | tail -1; "$PROBE" CHIE | tail -1; } | tee "$LOG"
"$PROBE" --set-chie 08 | tee -a "$LOG" || { restore; exit 1; }
for t in $(seq 10 10 "$N"); do sleep 10; echo "t=${t}s $(pmset -g batt | tr '\n' ' ')" | tee -a "$LOG"; done
restore
sleep 15
{ echo "== $(date) after restore"; pmset -g batt | tail -1; "$PROBE" CHIE | tail -1; } | tee -a "$LOG"
