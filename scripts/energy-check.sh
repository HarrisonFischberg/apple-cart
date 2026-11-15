#!/bin/bash
# T023: idle CPU of the Release build. Usage: energy-check.sh <app> <off|on> [runs] [seconds]
# Quits any running Apple Cart, sets the tool switches, launches, settles 30 s, then
# reads the process's own CPU time before and after each window. Restores the old switches.
APP="$1"; MODE="$2"; RUNS="${3:-5}"; SECS="${4:-300}"
DOM=app.rarecreatures.applecart
ALL=(battery system keepAwake clipboard copyText readQR breakReminders uninstaller cleaner diskMap updates quickToggles volumeGuard cleaningMode flushDNS)
BACKUP=$(defaults export $DOM - 2>/dev/null)
pkill -x AppleCart; sleep 2
if [ "$MODE" = on ]; then defaults write $DOM enabledFeatures -array "${ALL[@]}"; else defaults delete $DOM enabledFeatures 2>/dev/null; fi
defaults write $DOM firstRunDone -bool true
open -g "$APP"; sleep 30
PID=$(pgrep -x AppleCart | head -1)
secs() { ps -o cputime= -p "$PID" | awk -F'[:]' '{ if (NF==3) print $1*3600+$2*60+$3; else print $1*60+$2 }'; }
for i in $(seq 1 "$RUNS"); do
  a=$(secs); sleep "$SECS"; b=$(secs)
  awk -v a="$a" -v b="$b" -v s="$SECS" -v i="$i" 'BEGIN{printf "run %d: %.3f%% (cpu %.2fs over %ds)\n", i, (b-a)/s*100, b-a, s}'
done
pkill -x AppleCart
[ -n "$BACKUP" ] && echo "$BACKUP" | defaults import $DOM - 
