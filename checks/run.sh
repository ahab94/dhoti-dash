#!/bin/bash
# Runs Godot with a wall-clock limit, because a script error makes headless
# Godot sit in the debugger forever. Usage: checks/run.sh SECONDS godot-args...
limit=$1; shift
GODOT=$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)
perl -e 'alarm shift; exec @ARGV' "$limit" "$GODOT" "$@"
