#!/bin/bash
# The autopilot must finish every race in the top three. A failure usually
# means a race change made it too hard; trace it with
#   godot --headless --fixed-fps 60 --path . -- --level=N --autopilot --exit-on-end --trace
set -uo pipefail
cd "$(dirname "$0")/.."
count=$(checks/run.sh 60 --headless --path . --script res://tests/level_count.gd 2>/dev/null | grep -o 'LEVELS [0-9]*' | cut -d' ' -f2)
fail=0
for ((i = 0; i < count; i++)); do
	line=$(checks/run.sh 400 --headless --fixed-fps 60 --path . -- --level=$i --autopilot --exit-on-end --no-slowmo --timeout=300 2>&1 | grep '^RESULT')
	echo "$line"
	echo "$line" | grep -qE ' finished pos=[123] ' || fail=1
done
[ $fail -eq 0 ] && echo "autoplay: all $count races in the top three" || { echo "autoplay: FAILED"; exit 1; }
