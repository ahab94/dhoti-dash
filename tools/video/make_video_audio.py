#!/usr/bin/env python3
"""Stingers for the marketing videos (not used in the game), synthesized with
the game's own audio helpers, so everything stays original.

    python3 tools/video/make_video_audio.py   ->  build/video_audio/*.wav

The music beds are the game's own loops (audio/music); make_videos.py reads
them from there.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import make_audio as A  # noqa: E402

OUT = os.path.join(A.HERE, "..", "build", "video_audio")


def w(name, samples, peak=0.89):
    A.write_wav(os.path.join(OUT, name + ".wav"), samples, peak)


def main():
    # A soft pop for every caption.
    w("pop", A.tone(950, 0.08, "sine", 0.5, decay=0.03, glide_to=380))
    # A whoosh on every cut.
    w("whoosh", A.noise(0.35, 0.4, decay=0.15, lowpass=500, sweep_to=4000, seed=3, attack=0.1))
    # Record scratch: "wait, what?"
    scratch = A.Track(0.45)
    scratch.add(0, A.noise(0.18, 0.6, decay=0.1, lowpass=3000, sweep_to=600, seed=4))
    scratch.add(0.2, A.noise(0.2, 0.5, decay=0.08, lowpass=800, sweep_to=3500, seed=5))
    w("scratch", scratch.buf)
    # A truck's two-tone "pom pom" horn, desi highway style.
    horn = A.Track(0.8)
    for i, f in enumerate([370, 330]):
        horn.add(i * 0.3, A.layer(A.tone(f, 0.26, "square", 0.25, lowpass=1600, detune=0.01),
                                  A.tone(f * 1.26, 0.26, "square", 0.18, lowpass=1600, detune=0.012)))
    w("horn", horn.buf)
    # Dhol roll building into a big hit: the drop before a knockout.
    roll = A.Track(1.4)
    for i in range(14):
        t = i * 0.07 * (1 - i * 0.025)
        roll.add(t, A.tilli(0.15 + i * 0.02, seed=200 + i))
    roll.add(0.95, A.layer(A.dagga(0.9), A.cymbal(0.5, 0.2)))
    w("dholroll", roll.buf)
    w("ding", A.layer(A.tone(1760, 0.6, "sine", 0.3, decay=0.2), A.tone(3520, 0.3, "sine", 0.1, decay=0.08)))


if __name__ == "__main__":
    main()
