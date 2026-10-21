#!/bin/bash
# Turns phone recordings into the game's voice lines.
#
# 1. Record each line on your phone (Voice Memos is fine), one file per line.
# 2. Name the files after the line, any audio format: chacha_oteri.m4a,
#    rival_scream.mp3, ... (the names are listed in voices_in/LINES.txt).
# 3. Put them in voices_in/ and run:  bash tools/import_voices.sh
#
# Each file is trimmed of silence at both ends, made mono 44.1 kHz and
# levelled, then written to audio/voice_rec/<line>.wav. The game picks them
# up on its next start; lines you skip simply stay silent.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p audio/voice_rec
shopt -s nullglob nocaseglob
n=0
for f in voices_in/*.{m4a,mp3,wav,ogg,aac,caf,flac}; do
	name=$(basename "${f%.*}")
	ffmpeg -y -loglevel error -i "$f" -ac 1 -ar 44100 \
		-af "silenceremove=start_periods=1:start_threshold=-40dB,areverse,silenceremove=start_periods=1:start_threshold=-40dB,areverse,loudnorm=I=-16:TP=-1.5" \
		"audio/voice_rec/$name.wav"
	echo "imported $name"
	n=$((n + 1))
done
echo "$n voice lines imported into audio/voice_rec/"
