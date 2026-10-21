#!/bin/bash
# Done when: the project imports, the smoke and gameplay tests pass, and the
# autopilot finishes every race in the top three.
set -euo pipefail
cd "$(dirname "$0")/.."
checks/run.sh 120 --headless --path . --import >/dev/null 2>&1 || true
out=$(checks/run.sh 60 --headless --path . --script res://tests/smoke_test.gd 2>&1) || { echo "$out"; exit 1; }
if echo "$out" | grep -qE "SCRIPT ERROR|triangulation failed" || ! echo "$out" | grep -q "SMOKE OK"; then echo "$out"; echo "smoke test failed"; exit 1; fi
out=$(checks/run.sh 60 --headless --path . --script res://tests/game_test.gd 2>&1) || { echo "$out"; exit 1; }
if echo "$out" | grep -qE "SCRIPT ERROR|FAIL:" || ! echo "$out" | grep -q "GAME OK"; then echo "$out"; echo "gameplay test failed"; exit 1; fi
bash checks/autoplay.sh | tail -1
echo "dhoti-dash: all good"
