#!/bin/bash
# Records raw gameplay (game sound effects, no music) for the marketing videos
# into build/footage/:
#   p-N.mp4      portrait 1080x1920, expert autopilot, race N (Shorts)
#   p-rook-N.mp4 portrait, the sloppy rookie bot: crashes, bites, the aunty
#   l-N.mp4      landscape 1920x1080, expert autopilot (trailer)
# Slow motion is on for knockouts and crashes (--slowmo). Each clip gets a
# .events file: "EVENT v=<video seconds> t=<race seconds> <name>" so captions
# and cuts can be timed exactly.
# Usage: bash tools/video/record_footage.sh [clip-name ...]   (default: all)
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT=$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)
out=build/footage
mkdir -p "$out"

# Movie Maker records at the project's window size and ignores --resolution,
# so each recording writes a temporary override.cfg (read at startup, it
# overrides project.godot) with the exact window size.
trap 'rm -f override.cfg' EXIT
window() {  # w h
	printf '[display]\nwindow/size/viewport_width=%s\nwindow/size/viewport_height=%s\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' "$1" "$2" "$1" "$2" > override.cfg
}

record() {  # name resolution level extra-flags...
	local name=$1 res=$2 level=$3; shift 3
	if [ -n "${ONLY:-}" ] && [[ " $ONLY " != *" $name "* ]]; then return; fi
	# Retry: on a busy machine (several sessions recording at once) a run can
	# die part-way. A clip only counts once Godot printed its RESULT line.
	local try
	for try in 1 2 3; do
		if [ "$res" = 1080x1920 ]; then window 1080 1920; else window 1920 1080; fi
		perl -e 'alarm shift; exec @ARGV' 1500 "$GODOT" --path . --write-movie "$out/$name.avi" --fixed-fps 30 \
			-- --level="$level" --clean --no-music --slowmo --exit-on-end --linger=1.5 --log-events --timeout=150 "$@" \
			| grep -E "^(EVENT|RESULT)" > "$out/$name.events" || true
		rm -f override.cfg
		grep -q RESULT "$out/$name.events" && break
		echo "$name: attempt $try failed, retrying"
		rm -f "$out/$name.avi"
	done
	grep -q RESULT "$out/$name.events" || { echo "$name: gave up"; return; }
	ffmpeg -loglevel error -y -i "$out/$name.avi" -c:v libx264 -preset fast -crf 16 \
		-pix_fmt yuv420p -c:a aac -b:a 192k "$out/$name.mp4"
	rm "$out/$name.avi"
	local size; size=$(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0:s=x "$out/$name.mp4")
	[ "$size" = "$res" ] || { echo "$name recorded at $size, expected $res"; exit 1; }
	echo "$name: $(grep RESULT "$out/$name.events")"
}

ONLY="$*"
for n in 0 1 2 3 4 5; do
	record "p-$n" 1080x1920 "$n" --autopilot
done
for n in 1 2 3 5; do
	record "p-rook-$n" 1080x1920 "$n" --rookie
done
for n in 1 4 5; do
	record "l-$n" 1920x1080 "$n" --autopilot
done
