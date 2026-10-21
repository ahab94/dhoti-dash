#!/usr/bin/env python3
"""Synthesizes every sound in Dhoti Dash from scratch: desi instruments
(dhol, tabla, tumbi, harmonium, shehnai) modelled with plain maths. No
samples, no third-party audio, Python standard library only.

    python3 tools/make_audio.py

Writes 16-bit mono WAVs (Godot compresses them on import):
  audio/sfx/*.wav       comedy effects, 44.1 kHz
  audio/music/*.wav     seamless loops (race, menu)

Loops are exact to the sample: notes that run past the end wrap round to the
start. The game sets the loop points when it loads them (scripts/sound.gd).
Fixed random seeds make the output identical on every run.
"""
import array
import math
import os
import random
import wave

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "audio")
TAU = 2 * math.pi

NOTE_INDEX = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6,
              "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def hz(note):
    """'D3', 'Bb4', 'F#2' -> frequency in Hz (A4 = 440)."""
    name, octave = note[:-1], int(note[-1])
    midi = 12 * (octave + 1) + NOTE_INDEX[name]
    return 440.0 * 2 ** ((midi - 69) / 12)


# --- Sound sources ---------------------------------------------------------

def tone(freq, dur, shape="sine", vol=0.3, attack=0.005, decay=None, release=0.03,
         glide_to=None, lowpass=None, detune=0.0, tremolo=0.0, tremolo_hz=0.0):
    """One note. `decay` = exponential fade time constant (None = sustain).
    `glide_to` slides the pitch, `detune` adds a second slightly sharp oscillator."""
    n = int(dur * SR)
    out = [0.0] * n
    p1 = p2 = 0.0
    y = 0.0
    k = 1 - math.exp(-TAU * lowpass / SR) if lowpass else None
    for i in range(n):
        t = i / SR
        f = freq if glide_to is None else freq * (glide_to / freq) ** (t / dur)
        p1 = (p1 + f / SR) % 1.0
        s = _wave(shape, p1)
        if detune:
            p2 = (p2 + f * (1 + detune) / SR) % 1.0
            s = 0.5 * (s + _wave(shape, p2))
        if k:
            y += k * (s - y)
            s = y
        env = min(1.0, t / attack) if attack > 0 else 1.0
        if decay:
            env *= math.exp(-t / decay)
        if t > dur - release:
            env *= max(0.0, (dur - t) / release)
        if tremolo:
            env *= 1 - tremolo * (0.5 + 0.5 * math.sin(TAU * tremolo_hz * t))
        out[i] = s * env * vol
    return out


def _wave(shape, p):
    if shape == "sine":
        return math.sin(TAU * p)
    if shape == "saw":
        return 2 * p - 1
    if shape == "square":
        return 1.0 if p < 0.5 else -1.0
    if shape == "tri":
        return 4 * abs(p - 0.5) - 1
    raise ValueError(shape)


def noise(dur, vol=0.3, decay=0.05, lowpass=None, highpass=None, seed=1, attack=0.001,
          sweep_to=None):
    """Filtered white noise burst. `sweep_to` moves the lowpass cutoff over time."""
    rng = random.Random(seed)
    n = int(dur * SR)
    out = [0.0] * n
    lo = hi_lp = 0.0
    for i in range(n):
        t = i / SR
        s = rng.uniform(-1, 1)
        if lowpass:
            fc = lowpass if sweep_to is None else lowpass * (sweep_to / lowpass) ** (t / dur)
            lo += (1 - math.exp(-TAU * fc / SR)) * (s - lo)
            s = lo
        if highpass:
            hi_lp += (1 - math.exp(-TAU * highpass / SR)) * (s - hi_lp)
            s = s - hi_lp
        env = min(1.0, t / attack) * (math.exp(-t / decay) if decay else 1.0)
        if t > dur - 0.01:
            env *= max(0.0, (dur - t) / 0.01)
        out[i] = s * env * vol
    return out


# --- Mixing ------------------------------------------------------------------

class Track:
    """A mono buffer. With loop=True, anything that runs past the end wraps
    to the start, so the file loops seamlessly."""

    def __init__(self, seconds, loop=False):
        self.buf = array.array("f", bytes(4 * int(seconds * SR)))
        self.loop = loop

    def add(self, start, samples, gain=1.0):
        b = self.buf
        n = len(b)
        i0 = int(start * SR)
        for i, s in enumerate(samples):
            j = i0 + i
            if j >= n:
                if not self.loop:
                    break
                j %= n
            b[j] += s * gain

    def mix(self, other, gain=1.0):
        self.add(0, other.buf, gain)

    def echo(self, delay, feedback=0.35, mix=0.3):
        """Feedback delay. On a loop, run it twice so the tail wraps too."""
        b = self.buf
        n = len(b)
        d = int(delay * SR)
        wet = array.array("f", bytes(4 * n))
        for _ in range(2 if self.loop else 1):
            for i in range(n):
                j = i - d
                if j < 0 and not self.loop:
                    continue
                wet[i] = b[j % n] + feedback * wet[j % n]
        for i in range(n):
            b[i] += wet[i] * mix


def write_wav(path, samples, peak=0.89):
    """Soft-clip, normalize to `peak`, write 16-bit mono."""
    m = max(1e-9, max(abs(s) for s in samples))
    data = array.array("h", (int(32767 * peak * math.tanh(1.2 * s / m) / math.tanh(1.2)) for s in samples))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", os.path.relpath(path, os.path.join(HERE, "..")))


def cat(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def at(offset, samples):
    """Prefix with silence."""
    return [0.0] * int(offset * SR) + samples


def layer(*parts):
    n = max(len(p) for p in parts)
    out = [0.0] * n
    for p in parts:
        for i, s in enumerate(p):
            out[i] += s
    return out




# --- Desi instruments ----------------------------------------------------------

def pluck(freq, dur, vol=0.3, decay=0.996, bright=1.0, buzz=0.0, seed=1):
    """Karplus-Strong string: a burst of noise in a delay line one period
    long, averaged a little more each pass, rings like a plucked string.
    High and bright = tumbi; with `buzz` (a soft clip on the bridge) and
    lower = something sitar-ish."""
    rng = random.Random(seed)
    period = max(2, int(SR / freq))
    line = [rng.uniform(-1, 1) * bright for _ in range(period)]
    n = int(dur * SR)
    out = [0.0] * n
    j = 0
    for i in range(n):
        a = line[j]
        b = line[(j + 1) % period]
        new = decay * 0.5 * (a + b)
        if buzz:
            new = new + buzz * (new - new ** 3 * 2.0) * 0.1
        line[j] = new
        j = (j + 1) % period
        env = 1.0 if i < n - 400 else (n - i) / 400
        out[i] = a * vol * env
    return out


def harmonium(freqs, dur, vol=0.12):
    """Free reeds: each note is two slightly detuned sawtooths, softened with
    a lowpass, swelling in as the bellows push, with a slow pulse."""
    return layer(*[tone(f, dur, "saw", vol, attack=0.08, release=0.12, lowpass=1500,
                        detune=0.006, tremolo=0.12, tremolo_hz=5.0) for f in freqs])


def shehnai(freq, dur, vol=0.22, from_freq=None):
    """Double reed: a bright, nasal buzz (saw through a lowpass), a wide
    vibrato, and an optional meend (glide) in from the previous note."""
    n = int(dur * SR)
    out = [0.0] * n
    p = 0.0
    y = 0.0
    k = 1 - math.exp(-TAU * 2600 / SR)
    for i in range(n):
        t = i / SR
        f = freq
        if from_freq:
            g = min(1.0, t / 0.08)
            f = from_freq + (freq - from_freq) * (g * g * (3 - 2 * g))
        f *= 1 + 0.012 * math.sin(TAU * 6.0 * t) * min(1.0, t / 0.15)
        p = (p + f / SR) % 1.0
        s = 0.6 * (2 * p - 1) + 0.4 * (1.0 if p < 0.3 else -1.0)
        y += k * (s - y)
        env = min(1.0, t / 0.03) * min(1.0, (dur - t) / 0.04)
        out[i] = y * env * vol
    return out


def dagga(vol=0.7):
    """The dhol's big bass side: a deep boom that drops in pitch."""
    return layer(tone(78, 0.4, "sine", vol, decay=0.16, glide_to=52),
                 noise(0.06, vol * 0.35, decay=0.02, lowpass=400, seed=21))


def tilli(vol=0.35, seed=31):
    """The dhol's thin stick side: a sharp, dry crack."""
    return layer(noise(0.08, vol, decay=0.025, highpass=1800, seed=seed),
                 tone(430, 0.06, "tri", vol * 0.5, decay=0.02))


def tabla_na(freq=720, vol=0.32):
    """Dayan (right drum) 'na': a ringing tone with a few overtones."""
    return layer(tone(freq, 0.35, "sine", vol, decay=0.12),
                 tone(freq * 2.0, 0.2, "sine", vol * 0.45, decay=0.06),
                 tone(freq * 3.0, 0.12, "sine", vol * 0.25, decay=0.03),
                 noise(0.02, vol * 0.4, decay=0.006, highpass=3000, seed=int(freq)))


def tabla_ge(vol=0.5, swoop=1.6):
    """Bayan (left drum) 'ge': the heel presses the skin and the pitch swoops up."""
    return tone(88, 0.5, "sine", vol, decay=0.2, glide_to=88 * swoop)


def clap(vol=0.18, seed=41):
    return cat(noise(0.012, vol, decay=0.005, highpass=1500, seed=seed),
               noise(0.012, vol, decay=0.005, highpass=1500, seed=seed + 1),
               noise(0.08, vol, decay=0.03, highpass=1200, seed=seed + 2))


def cymbal(dur=0.9, vol=0.2, seed=51):
    return noise(dur, vol, decay=dur * 0.35, highpass=5000, seed=seed)


# --- Music -------------------------------------------------------------------
# Race: a bhangra loop in D (Khamaj flavour: the 7th is flat), 152 BPM.
# Dhol chaal, handclaps, a tumbi riff, harmonium chords, and a shehnai tune.

BPM = 152
BEAT = 60 / BPM
BAR = 4 * BEAT
S16 = BEAT / 4
CHORDS = [["D3", "F#3", "A3"], ["C3", "E3", "G3"], ["G2", "B2", "D3"], ["D3", "F#3", "A3"]]
TUMBI = [(0, "A5"), (1, "A5"), (3, "A5"), (4, "D6"), (6, "A5"), (7, "B5"),
         (8, "A5"), (10, "G5"), (12, "F#5"), (13, "G5"), (14, "A5")]   # 8th-note slots, 2 bars
SHEHNAI = [  # (beat within 8 bars, note, beats)
    (0, "D5", 1), (1, "E5", 0.5), (1.5, "F#5", 0.5), (2, "A5", 1.5), (3.5, "G5", 0.5),
    (4, "F#5", 1), (5, "E5", 1), (6, "D5", 2),
    (8, "C5", 1), (9, "D5", 0.5), (9.5, "E5", 0.5), (10, "G5", 1.5), (11.5, "F#5", 0.5),
    (12, "E5", 1), (13, "D5", 1), (14, "C5", 2),
    (16, "D5", 0.5), (16.5, "F#5", 0.5), (17, "A5", 1), (18, "B5", 1), (19, "A5", 1),
    (20, "C6", 1.5), (21.5, "B5", 0.5), (22, "A5", 2),
    (24, "G5", 1), (25, "F#5", 1), (26, "E5", 1), (27, "C5", 1),
    (28, "D5", 3),
]


def race_song():
    bars = 8
    tr = Track(bars * BAR, loop=True)
    for bar in range(bars):
        t0 = bar * BAR
        for s16 in [0, 6, 8]:
            tr.add(t0 + s16 * S16, dagga())
        for s16 in [4, 10, 12, 14]:
            tr.add(t0 + s16 * S16, tilli(seed=bar * 16 + s16))
        for b in [1, 3]:
            tr.add(t0 + b * BEAT, clap(seed=bar * 4 + b))
        tr.add(t0, harmonium([hz(n) for n in CHORDS[bar % 4]], BAR * 0.95, 0.07))
    for rep in range(bars // 2):
        for slot, note in TUMBI:
            tr.add(rep * 2 * BAR + slot * BEAT / 2,
                   pluck(hz(note), 0.35, 0.22, decay=0.993, seed=slot + rep * 20))
    prev = None
    for start, note, length in SHEHNAI:
        f = hz(note)
        tr.add(start * BEAT, shehnai(f, length * BEAT + 0.05, 0.2, from_freq=prev))
        prev = f
    tr.echo(BEAT * 0.75, feedback=0.25, mix=0.15)
    return tr.buf


# Menu: an easy keherwa theka on tabla (8 beats: dha ge na ti na ka dhi na),
# 96 BPM, a plucked sitar-ish line and a harmonium drone.

MENU_BPM = 96
MB = 60 / MENU_BPM
SITAR = [(0, "D4"), (1.5, "F#4"), (2, "A4"), (3, "G4"), (4, "F#4"), (5.5, "E4"), (6, "D4"),
         (8, "A4"), (9.5, "B4"), (10, "C5"), (11, "B4"), (12, "A4"), (13.5, "G4"), (14, "F#4")]


def menu_song():
    beats = 16
    tr = Track(beats * MB, loop=True)
    bols = ["dha", "ge", "na", "ti", "na", "ka", "dhi", "na"]
    for b in range(beats):
        bol = bols[b % 8]
        t = b * MB
        if bol in ("dha", "dhi"):
            tr.add(t, layer(tabla_na(700), tabla_ge(0.45)))
        elif bol == "ge":
            tr.add(t, tabla_ge(0.4, 1.3))
        elif bol in ("ti", "ka"):
            tr.add(t, tabla_na(1050, 0.2))
        else:
            tr.add(t, tabla_na(720, 0.28))
        tr.add(t + MB / 2, tabla_na(980, 0.1))   # a soft fill on the off-beat
    tr.add(0, harmonium([hz("D3"), hz("A3")], beats * MB, 0.06))
    for start, note in SITAR:
        tr.add(start * MB, pluck(hz(note), 1.6, 0.3, decay=0.9985, buzz=0.6, seed=int(start * 10)))
    tr.echo(MB * 0.5, feedback=0.3, mix=0.18)
    return tr.buf


def music():
    d = os.path.join(OUT, "music")
    write_wav(os.path.join(d, "race.wav"), race_song(), peak=0.8)
    write_wav(os.path.join(d, "menu.wav"), menu_song(), peak=0.8)


# --- Sound effects -------------------------------------------------------------

def bell_ding(vol=0.3):
    """A bicycle bell: a struck steel dome, so the overtones are not neat
    multiples (1, 2.76, 5.4 times the base), each dying at its own rate."""
    base = 2350
    return layer(tone(base, 0.6, "sine", vol, decay=0.25, tremolo=0.3, tremolo_hz=28),
                 tone(base * 2.76, 0.4, "sine", vol * 0.5, decay=0.12),
                 tone(base * 5.4, 0.2, "sine", vol * 0.25, decay=0.05))


def moo():
    """A buffalo: a low sawtooth groan that rises, then sags, through a
    lowpass that opens as the mouth opens."""
    n = int(1.3 * SR)
    out = [0.0] * n
    p = 0.0
    y = 0.0
    for i in range(n):
        t = i / SR
        f = 95 + 40 * math.sin(math.pi * min(1.0, t / 1.1)) - 15 * t
        p = (p + f / SR) % 1.0
        s = 2 * p - 1
        fc = 300 + 700 * math.sin(math.pi * min(1.0, t / 1.2))
        y += (1 - math.exp(-TAU * fc / SR)) * (s - y)
        env = min(1.0, t / 0.15) * min(1.0, (1.3 - t) / 0.3)
        out[i] = y * env * 0.5
    return out


def sfx():
    d = os.path.join(OUT, "sfx")
    w = lambda name, s, peak=0.89: write_wav(os.path.join(d, name + ".wav"), s, peak)
    # Tring tring: two quick strikes of the bell.
    bell = Track(0.9)
    bell.add(0, bell_ding())
    bell.add(0.16, bell_ding(0.26))
    w("bell", bell.buf)
    # Whoosh of a swing.
    w("swing", noise(0.22, 0.35, decay=0.12, lowpass=600, sweep_to=3500, seed=61, attack=0.06))
    # DHISHOOM: the film-fight punch. A deep thump, a slap, and a long tail.
    hit = Track(0.8)
    hit.add(0, tone(120, 0.5, "sine", 0.7, decay=0.12, glide_to=45))
    hit.add(0, noise(0.12, 0.5, decay=0.03, lowpass=2500, seed=62))
    hit.add(0.01, noise(0.6, 0.15, decay=0.2, lowpass=900, seed=63))
    hit.echo(0.07, feedback=0.3, mix=0.3)
    w("dhishoom", hit.buf)
    # A lighter thwack for rivals fighting each other off to the side.
    w("thwack", layer(tone(200, 0.2, "sine", 0.4, decay=0.05, glide_to=90),
                      noise(0.08, 0.35, decay=0.02, lowpass=3000, seed=64)))
    # Crash: a thud, rattling metal, and the bell jangling as the cycle hits the road.
    crash = Track(1.2)
    crash.add(0, layer(tone(110, 0.4, "sine", 0.6, decay=0.1, glide_to=45),
                       noise(0.6, 0.4, decay=0.2, lowpass=4000, sweep_to=600, seed=65)))
    for i in range(4):
        crash.add(0.08 + i * 0.09, bell_ding(0.12 - i * 0.02))
    w("crash", crash.buf)
    w("moo", moo())
    # Pothole: a jolt and a rattle of the carrier.
    bump = Track(0.4)
    bump.add(0, tone(90, 0.25, "sine", 0.6, decay=0.06, glide_to=60))
    for i in range(5):
        bump.add(0.03 + i * 0.035, noise(0.03, 0.2, decay=0.01, highpass=2500, seed=70 + i))
    w("bump", bump.buf)
    w("splash", noise(0.5, 0.45, decay=0.15, lowpass=2500, sweep_to=700, seed=71))
    # Speed breaker hop: the tabla's 'ge' swooping up, as comic as it gets.
    w("hop", tone(90, 0.5, "sine", 0.7, decay=0.25, glide_to=210))
    # Chai: a steel glass clink and a satisfied slurp.
    chai = Track(0.8)
    chai.add(0, layer(tone(3100, 0.3, "sine", 0.25, decay=0.08), tone(4650, 0.2, "sine", 0.12, decay=0.05)))
    chai.add(0.2, noise(0.4, 0.2, decay=0.25, lowpass=1800, sweep_to=500, seed=72, attack=0.05))
    w("chai", chai.buf)
    # Jalebi: a sugar-rush run up a scale on the sitar.
    jal = Track(0.9)
    for i, n in enumerate(["D5", "E5", "F#5", "A5", "B5", "D6"]):
        jal.add(i * 0.06, pluck(hz(n), 0.5, 0.25, decay=0.995, seed=80 + i))
    w("jalebi", jal.buf)
    # New weapon: a double dhol boom.
    arm = Track(0.7)
    arm.add(0, dagga(0.8))
    arm.add(0.15, dagga(0.8))
    arm.add(0.15, tilli(0.4))
    w("weapon", arm.buf)
    # OUT! A tabla tihai (the same phrase three times, landing on a big dha)
    # and a cymbal, like an umpire's finger going up.
    out = Track(1.6)
    for rep in range(3):
        base = rep * 0.27
        out.add(base, tabla_na(760, 0.3))
        out.add(base + 0.09, tabla_na(1000, 0.2))
        out.add(base + 0.18, tabla_na(760, 0.3))
    out.add(0.82, layer(tabla_na(700, 0.4), tabla_ge(0.6), dagga(0.6)))
    out.add(0.82, cymbal(0.8, 0.15))
    w("out", out.buf)
    # Aunty! The family-drama TV sting: three heavy hits, zooming in on a face.
    drama = Track(1.9)
    for i in range(3):
        t = i * 0.42
        drama.add(t, layer(dagga(0.8), cymbal(0.5, 0.18, seed=90 + i),
                           harmonium([hz("D3"), hz("F3"), hz("A3")], 0.35, 0.14)))
    drama.add(1.26, harmonium([hz("C#3"), hz("E3"), hz("G3"), hz("A#3")], 0.6, 0.14))
    drama.echo(0.12, feedback=0.35, mix=0.35)
    w("aunty", drama.buf)
    # Countdown: tabla 'na' ticks, and a big 'dha' with a dhol boom for GO.
    w("tick", tabla_na(900, 0.35))
    w("go", layer(tabla_na(700, 0.4), tabla_ge(0.6), dagga(0.6), cymbal(0.6, 0.12)))
    # Win: a bright shehnai flourish over dhol.
    win = Track(2.4)
    prev = None
    t = 0.0
    for n, l in [("D5", 0.15), ("F#5", 0.15), ("A5", 0.15), ("D6", 0.5), ("C6", 0.15), ("D6", 1.0)]:
        f = hz(n)
        win.add(t, shehnai(f, l + 0.05, 0.25, from_freq=prev))
        prev = f
        t += l
    for s in [0, 0.2, 0.3, 0.6, 0.75, 1.1]:
        win.add(s, dagga(0.6))
    win.add(1.1, cymbal(1.0, 0.15))
    w("win", win.buf)
    # Retired hurt: a sad shehnai drooping down, with a tired tabla.
    sad = Track(3.0)
    prev = None
    t = 0.0
    for n, l in [("A4", 0.45), ("G4", 0.45), ("F4", 0.45), ("E4", 1.4)]:
        f = hz(n)
        sad.add(t, shehnai(f, l, 0.22, from_freq=prev))
        prev = f
        t += l
    sad.add(t - 1.4, tabla_ge(0.5, 0.7))
    w("sad", sad.buf)
    w("click", tabla_na(1100, 0.3))
    # Cartoon effects: where cartoons get their emotion.
    # Slide whistle falling: the classic "here he goes" for a crash.
    w("whistle_down", tone(1900, 0.9, "sine", 0.3, attack=0.02, glide_to=320, tremolo=0.2, tremolo_hz=12))
    w("whistle_up", tone(600, 0.4, "sine", 0.3, attack=0.02, glide_to=1800, tremolo=0.2, tremolo_hz=14))
    # Bonk: a hollow wood block plus a dull knock.
    w("bonk", layer(tone(820, 0.25, "sine", 0.5, decay=0.06, glide_to=600),
                    tone(1640, 0.12, "sine", 0.2, decay=0.03),
                    noise(0.03, 0.3, decay=0.008, lowpass=3000, seed=140)))
    # Boing: a spring wobbling.
    n = int(0.5 * SR)
    boing = [0.0] * n
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = 230 * (1 + 1.3 * t / 0.5) + 160 * math.sin(TAU * 13 * t) * math.exp(-t / 0.25)
        ph = (ph + f / SR) % 1.0
        boing[i] = math.sin(TAU * ph) * min(1.0, t / 0.005) * math.exp(-t / 0.2) * 0.45
    w("boing", boing)
    # Dizzy: little birds tweeting round his head.
    dizzy = Track(1.6)
    for i in range(6):
        f = 2600 + 500 * (i % 3)
        dizzy.add(0.1 + i * 0.22, layer(tone(f, 0.09, "sine", 0.18, glide_to=f * 1.3),
                                        at(0.1, tone(f * 1.1, 0.08, "sine", 0.15, glide_to=f * 0.9))))
    w("dizzy", dizzy.buf)
    # Sad trombone-ish shehnai already exists; a cartoon "wah-wah" for losing a weapon fight.
    w("splat", layer(noise(0.25, 0.5, decay=0.06, lowpass=900, seed=150),
                     tone(160, 0.2, "sine", 0.5, decay=0.05, glide_to=70)))
    # Village animals and machines.
    bark = Track(0.7)
    for i, f in enumerate([520, 600]):
        bark.add(i * 0.22, layer(tone(f, 0.12, "saw", 0.3, glide_to=f * 0.6, lowpass=1800),
                                 noise(0.1, 0.25, decay=0.03, lowpass=2500, seed=100 + i)))
    w("bark", bark.buf)
    w("yelp", tone(900, 0.35, "saw", 0.3, glide_to=1500, lowpass=2500, tremolo=0.4, tremolo_hz=20))
    snap = Track(0.4)
    snap.add(0, layer(tone(300, 0.15, "saw", 0.3, glide_to=200, lowpass=900),
                      noise(0.05, 0.4, decay=0.01, highpass=2000, seed=110)))
    w("bite", snap.buf)
    # A goat: a bleat is a nasal tone with a fast, shaky vibrato.
    w("baa", tone(420, 0.6, "saw", 0.3, attack=0.03, lowpass=1500, tremolo=0.6, tremolo_hz=11))
    cl = Track(0.5)
    for i, f in enumerate([700, 760, 1050]):
        cl.add(i * 0.12, layer(tone(f, 0.07, "square", 0.18, glide_to=f * 1.5, lowpass=2200),
                               noise(0.06, 0.1, decay=0.03, lowpass=3000, seed=120 + i)))
    w("cluck", cl.buf)
    # Bullock bells: a few small, high, jangling strikes.
    bells = Track(1.0)
    for i in range(6):
        bells.add(i * 0.14, layer(tone(2800 + 300 * (i % 3), 0.4, "sine", 0.15, decay=0.12),
                                  tone(7300 + 500 * (i % 2), 0.2, "sine", 0.06, decay=0.05)))
    w("bells", bells.buf)
    # Tractor: a chugging diesel putt-putt.
    tr = Track(1.2)
    for i in range(10):
        tr.add(i * 0.11, layer(tone(65, 0.1, "saw", 0.5, decay=0.04, lowpass=400),
                               noise(0.06, 0.25, decay=0.03, lowpass=600, seed=130 + i)))
    w("tractor", tr.buf)


def main():
    sfx()
    music()


if __name__ == "__main__":
    main()
