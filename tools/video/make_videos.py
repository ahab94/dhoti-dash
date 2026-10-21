#!/usr/bin/env python3
"""Builds the marketing videos (Shorts and a trailer) from recorded footage.

    bash tools/video/record_footage.sh          # raw gameplay -> build/footage/
    python3 tools/video/make_video_audio.py     # stingers -> build/video_audio/
    /usr/bin/python3 tools/video/make_videos.py [video-id ...]

Needs Pillow (captions) and ffmpeg. Writes build/videos/<id>.mp4 and
docs/marketing/youtube.md (titles, descriptions, tags for uploading).

A video is a list of beats. Each beat is cut from a clip around a *moment*
(the nth time an event happened, read from the clip's .events file), so
re-recorded footage keeps its cuts. A beat can carry a caption and stingers.
Audio = the clip's game sounds + one of the game's music loops + stingers.
Adapted from Air Superiority Complex's video tools.
"""
import json
import os
import re
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FOOTAGE = os.path.join(ROOT, "build", "footage")
OUT = os.path.join(ROOT, "build", "videos")
VIDEO_AUDIO = os.path.join(ROOT, "build", "video_audio")
FONT = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"

PLAY = "https://ahab94.github.io/dhoti-dash/"
PLAY_SHORT = "ahab94.github.io/dhoti-dash"   # shown on screen
REPO = "https://github.com/ahab94/dhoti-dash"
RELEASES = REPO + "/releases/latest"

SUN = (255, 210, 63)        # the game's yellow
CREAM = (255, 248, 231)
INK = (58, 42, 26)
RED = (230, 57, 70)
SKY = (255, 179, 92)

LINKS = f"""⭐ Open source on GitHub, a star helps a lot: {REPO}
⬇ Windows / Mac / Linux downloads: {RELEASES}"""

BASE_TAGS = ["dhoti dash", "indie game", "desi game", "free game", "browser game", "godot", "gamedev",
             "cycle race", "combat racing", "funny game", "desi comedy", "chacha"]
HASHTAGS = ["DhotiDash", "indiegame", "desi", "gamedev", "funnygames"]


def description(blurb):
    return f"""▶ PLAY FREE in your browser: {PLAY}

{blurb}

{LINKS}

Dhoti Dash is a free, satirical desi combat-cycling game. Chacha Jee, 72, rides his old black cycle on everyday errands: beat the mohalla's riders with a chhatri, chappal or belan, dodge cows, stray dogs and baraats, and escape the rishta aunty. Made with the Godot engine; every picture and sound is made in code.

{" ".join("#" + t for t in HASHTAGS)}"""


def frame_size(orient):
    return (1080, 1920) if orient == "portrait" else (1920, 1080)


def font(size):
    return ImageFont.truetype(FONT, size)


def sfx_path(name):
    """Video stingers (build/video_audio) first, then the game's own (audio/sfx)."""
    for folder in (VIDEO_AUDIO, os.path.join(ROOT, "audio", "sfx")):
        path = os.path.join(folder, name + ".wav")
        if os.path.exists(path):
            return path
    raise FileNotFoundError(name)


# --- moments -----------------------------------------------------------------

_events = {}


def events(clip):
    if clip not in _events:
        rows = []
        with open(os.path.join(FOOTAGE, clip + ".events")) as f:
            for line in f:
                m = re.match(r"EVENT v=([\d.]+) t=([\d.-]+) (.*)", line.strip())
                if m:
                    rows.append((float(m.group(1)), m.group(3)))
        _events[clip] = rows
    return _events[clip]


def moment(clip, name, nth=0):
    """Video time of the nth event named `name` (whole first word, so "crash"
    doesn't also match "crash_into"; a name with a space matches a prefix)."""
    hits = [v for v, e in events(clip) if (e.startswith(name) if " " in name else e.split(" ")[0] == name)]
    if not hits:
        raise KeyError(f"{clip}: no '{name}' event")
    return hits[min(nth, len(hits) - 1)]


def count(clip, name):
    return sum(1 for _, e in events(clip) if e.startswith(name))


def clip_length(clip):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0",
                          os.path.join(FOOTAGE, clip + ".mp4")], capture_output=True, text=True, check=True).stdout
    return float(out.strip())


# --- captions and cards ------------------------------------------------------

def draw_centered(draw, lines, y_center, size, fill, width, stroke=10, line_gap=1.12, stroke_fill=INK):
    f = font(size)
    heights = [size * line_gap] * len(lines)
    y = y_center - sum(heights) / 2
    for line, h in zip(lines, heights):
        w = draw.textlength(line, font=f)
        draw.text(((width - w) / 2, y), line, font=f, fill=fill, stroke_width=stroke, stroke_fill=stroke_fill)
        y += h


def caption_png(path, text, style, orient):
    """Full-frame transparent PNG with the caption placed for the format."""
    W, H = frame_size(orient)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    lines = text.split("\n") if text else []
    portrait = orient == "portrait"
    if style == "hook":
        # The top band of a Short (sky in our portrait framing), white card.
        size = 84
        while size > 44 and max(d.textlength(l, font=font(size)) for l in lines) > W - 150:
            size -= 4                      # shrink to fit the card
        f = font(size)
        box_w = min(W - 60, max(d.textlength(l, font=f) for l in lines) + 90)
        box_h = len(lines) * size * 1.15 + 50
        cy = H * (0.16 if portrait else 0.14)
        d.rounded_rectangle([(W - box_w) / 2, cy - box_h / 2, (W + box_w) / 2, cy + box_h / 2], 36,
                            fill=(255, 255, 255, 240), outline=INK, width=6)
        draw_centered(d, lines, cy, size, INK, W, stroke=0)
    elif style == "big":
        # Punchlines mid-sky, above the riders.
        size = 140 if portrait else 130
        while size > 60 and max(d.textlength(l, font=font(size)) for l in lines) > W - 90:
            size -= 6
        draw_centered(d, lines, H * (0.36 if portrait else 0.3), size, SUN, W, stroke=14)
    elif style == "say":
        # A speech line, smaller, under the punchline area.
        draw_centered(d, lines, H * (0.45 if portrait else 0.42), 70, CREAM, W, stroke=9)
    elif style == "cta":
        cy = H * (0.53 if portrait else 0.78)   # below the punchlines, above Chacha
        f1, f2 = font(56 if portrait else 60), font(40)
        l1, l2 = "PLAY FREE IN YOUR BROWSER", PLAY_SHORT
        w = min(W - 60, max(d.textlength(l1, font=f1), d.textlength(l2, font=f2)) + 140)
        h = 200
        d.rounded_rectangle([(W - w) / 2, cy - h / 2, (W + w) / 2, cy + h / 2], 34, fill=SUN + (250,), outline=INK, width=6)
        tx = (W - d.textlength(l1, font=f1)) / 2 - 10
        d.polygon([(tx - 46, cy - 64), (tx - 46, cy - 20), (tx - 8, cy - 42)], fill=INK)
        d.text(((W - d.textlength(l1, font=f1)) / 2 + 12, cy - 78), l1, font=f1, fill=INK)
        d.text(((W - d.textlength(l2, font=f2)) / 2, cy + 20), l2, font=f2, fill=(90, 60, 30))
    else:  # "low": landscape lower third
        size = 72
        f = font(size)
        box_w = max(d.textlength(l, font=f) for l in lines) + 80
        box_h = len(lines) * size * 1.15 + 40
        y0 = H - box_h - 110
        d.rounded_rectangle([(W - box_w) / 2, y0, (W + box_w) / 2, y0 + box_h], 28, fill=(40, 25, 10, 200))
        draw_centered(d, lines, y0 + box_h / 2, size, (255, 255, 255), W, stroke=0)
    img.save(path)


def card_png(path, orient, title_lines, kind):
    """Intro / outro cards: the game's sunset colours."""
    W, H = frame_size(orient)
    img = Image.new("RGB", (W, H), SKY)
    d = ImageDraw.Draw(img)
    for i in range(H):   # sunset gradient
        k = i / H
        c = tuple(int(a + (b - a) * k) for a, b in zip((255, 160, 70), (255, 226, 168)))
        d.line([0, i, W, i], fill=c)
    portrait = orient == "portrait"
    if kind == "intro":
        draw_centered(d, title_lines, H * 0.45, 120 if portrait else 110, SUN, W, stroke=14)
    else:
        draw_centered(d, ["DHOTI DASH"], H * (0.3 if portrait else 0.28), 150 if portrait else 140, SUN, W, stroke=16)
        draw_centered(d, ["PLAY FREE", "IN YOUR BROWSER"] if portrait else ["PLAY FREE IN YOUR BROWSER"],
                      H * (0.5 if portrait else 0.55), 86 if portrait else 78, CREAM, W, stroke=10)
        draw_centered(d, [PLAY_SHORT], H * (0.62 if portrait else 0.7), 48, (255, 255, 255), W, stroke=7)
        draw_centered(d, ["free & open source on GitHub"], H * (0.69 if portrait else 0.8), 44, INK, W, stroke=0)
    img.save(path)


def thumbnail_png(path, clip, t, lines):
    W, H = 1280, 720
    tmp = path + ".frame.png"
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-ss", f"{t:.2f}", "-i", os.path.join(FOOTAGE, clip + ".mp4"),
                    "-frames:v", "1", "-vf", f"scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H}", tmp], check=True)
    img = Image.open(tmp).convert("RGB")
    os.remove(tmp)
    d = ImageDraw.Draw(img, "RGBA")
    d.rectangle([0, 0, W, H], fill=(0, 0, 0, 60))
    draw_centered(d, list(lines), H * 0.3, 140, SUN, W, stroke=14)
    img.save(path)


# --- building ----------------------------------------------------------------

def run(cmd):
    subprocess.run(cmd, check=True)


def atempo_chain(speed):
    parts, s = [], speed
    while s > 2.0:
        parts.append("atempo=2.0")
        s /= 2.0
    while s < 0.5:
        parts.append("atempo=0.5")
        s /= 0.5
    parts.append(f"atempo={s:.4f}")
    return ",".join(parts)


def cut(src, start, end, speed, path, W, H):
    run(["ffmpeg", "-loglevel", "error", "-y", "-ss", f"{start:.2f}", "-to", f"{end:.2f}",
         "-i", os.path.join(FOOTAGE, src + ".mp4"), "-vf", f"setpts=PTS/{speed},scale={W}:{H},fps=30",
         "-af", atempo_chain(speed) + ",aresample=48000", "-c:a", "aac", "-b:a", "192k", "-ac", "2",
         "-c:v", "libx264", "-preset", "fast", "-crf", "16", "-pix_fmt", "yuv420p", path])


def still(png, seconds, path):
    run(["ffmpeg", "-loglevel", "error", "-y", "-loop", "1", "-t", str(seconds), "-i", png,
         "-f", "lavfi", "-t", str(seconds), "-i", "anullsrc=r=48000:cl=stereo", "-c:a", "aac", "-b:a", "192k",
         "-shortest", "-vf", "fps=30,format=yuv420p", "-c:v", "libx264", "-preset", "fast", "-crf", "16", path])


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True, check=True).stdout
    return float(out.strip())


def resolve(beat):
    """A beat's clip window in source seconds."""
    clip = beat["clip"]
    if "at" in beat:
        name, nth = beat["at"] if isinstance(beat["at"], tuple) else (beat["at"], 0)
        t = moment(clip, name, nth)
        a, b = t - beat.get("pre", 2.0), t + beat.get("post", 2.5)
    else:
        a, b = beat["from"], beat.get("to", clip_length(clip))
    return clip, max(0.0, a), min(b, clip_length(clip)), beat.get("speed", 1.0)


def build(v, tmp):
    W, H = frame_size(v["orient"])
    parts = []
    t_video = 0.0
    captions, cues = [], []
    if "intro" in v:
        text, secs = v["intro"]
        png = os.path.join(tmp, "intro.png")
        card_png(png, v["orient"], text.split("\n"), "intro")
        parts.append(os.path.join(tmp, "intro.mp4"))
        still(png, secs, parts[-1])
        cues.append((0.05, "dholroll", 0.6))
        t_video += secs
    for i, beat in enumerate(v["beats"]):
        clip, a, b, speed = resolve(beat)
        parts.append(os.path.join(tmp, f"seg{i}.mp4"))
        cut(clip, a, b, speed, parts[-1], W, H)
        length = (b - a) / speed
        # Captions and stingers are timed in seconds from the beat's start,
        # or from the moment ("@"), which sits `pre` seconds in.
        anchor = beat.get("pre", 2.0) / speed if "at" in beat else 0.0
        for c in beat.get("caps", []):
            t0, t1, text, style = c
            captions.append((t_video + anchor + t0, t_video + anchor + t1, text, style))
        for c in beat.get("sfx", []):
            dt, name = c[0], c[1]
            cues.append((t_video + anchor + dt, name, c[2] if len(c) > 2 else 1.0))
        if i > 0 and v.get("cut_whoosh", True):
            cues.append((max(0.0, t_video - 0.15), "whoosh", 0.45))
        t_video += length
    gameplay_end = t_video
    if v.get("outro"):
        png = os.path.join(tmp, "outro.png")
        card_png(png, v["orient"], [], "outro")
        parts.append(os.path.join(tmp, "outro.mp4"))
        still(png, v["outro"], parts[-1])
        cues.append((gameplay_end, "ding", 0.8))
    else:
        # Every Short ends with the play link on screen: links in Shorts
        # descriptions aren't clickable, so viewers need to see the address.
        captions.append((max(0.0, gameplay_end - 3.0), gameplay_end, "", "cta"))
        cues.append((max(0.0, gameplay_end - 3.0), "ding", 0.7))
    if v.get("hook"):
        captions.append((0.0, v.get("hook_secs", 3.0), v["hook"], "hook"))

    listing = os.path.join(tmp, "list.txt")
    with open(listing, "w") as f:
        f.writelines(f"file '{p}'\n" for p in parts)
    joined = os.path.join(tmp, "joined.mp4")
    run(["ffmpeg", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", listing, "-c", "copy", joined])
    total = duration(joined)

    inputs, filters, last = [], [], "[0:v]"
    for i, (t0, t1, text, style) in enumerate(captions):
        png = os.path.join(tmp, f"cap{i}.png")
        caption_png(png, text, style, v["orient"])
        inputs += ["-loop", "1", "-t", f"{total:.2f}", "-i", png]
        filters.append(f"{last}[{i + 1}:v]overlay=0:0:enable='between(t,{t0:.2f},{t1:.2f})'[v{i}]")
        last = f"[v{i}]"
        if style in ("big", "say") and text:
            cues.append((t0, "pop", 0.4))
    base = len(captions) + 1
    music = os.path.join(ROOT, "audio", "music", v.get("music", "race") + ".wav")
    audio_inputs = ["-stream_loop", "-1", "-i", music]
    mix = ["[0:a]volume=1.0[g]", f"[{base}:a]volume={v.get('music_volume', 0.45)}[m]"]
    labels = ["[g]", "[m]"]
    for j, (t, name, vol) in enumerate(cues):
        audio_inputs += ["-i", sfx_path(name)]
        ms = max(0, int(t * 1000))
        mix.append(f"[{base + 1 + j}:a]adelay={ms}|{ms},volume={vol * 1.2:.2f}[s{j}]")
        labels.append(f"[s{j}]")
    mix.append(f"{''.join(labels)}amix=inputs={len(labels)}:normalize=0:duration=first,atrim=0:{total:.2f},"
               f"loudnorm=I=-14:TP=-1.5:LRA=11,afade=t=in:d=0.2,afade=t=out:st={total - 0.8:.2f}:d=0.8,"
               f"aresample=48000[a]")
    graph = ";".join(filters + [";".join(mix)])
    out = os.path.join(OUT, v["id"] + ".mp4")
    run(["ffmpeg", "-loglevel", "error", "-y", "-i", joined, *inputs, *audio_inputs,
         "-filter_complex", graph, "-map", last, "-map", "[a]",
         "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-r", "30",
         "-c:a", "aac", "-b:a", "192k", "-ac", "2", "-movflags", "+faststart", "-t", f"{total:.2f}", out])
    print(f"{v['id']}: {total:.1f}s -> {os.path.relpath(out, ROOT)}")
    return total


def write_metadata(videos, lengths):
    path = os.path.join(ROOT, "docs", "marketing", "youtube.md")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lines = ["# YouTube uploads", "",
             "Generated by `tools/video/make_videos.py`. Audience: **No, it's not made for kids** (family-friendly, all ages).",
             "Upload as **Private** first, then publish after review.", ""]
    for v in videos:
        lines += [f"## {v['id']} ({'Short' if v['orient'] == 'portrait' else 'video'}, {lengths.get(v['id'], 0):.0f}s)", "",
                  f"**Title:** {v['title']}", "", "**Description:**", "", "```", description(v["blurb"]), "```", "",
                  f"**Tags:** {', '.join(BASE_TAGS + v.get('tags', []))}", ""]
    with open(path, "w") as f:
        f.write("\n".join(lines))
    with open(os.path.join(OUT, "metadata.json"), "w") as f:
        json.dump([{"id": v["id"], "file": v["id"] + ".mp4", "title": v["title"], "description": description(v["blurb"]),
                    "tags": BASE_TAGS + v.get("tags", []), "short": v["orient"] == "portrait"} for v in videos], f, indent=2)
    print("wrote", os.path.relpath(path, ROOT))


def main():
    from videos import VIDEOS   # the video list lives in videos.py, next to this file
    os.makedirs(OUT, exist_ok=True)
    wanted = set(sys.argv[1:])
    lengths = {}
    for v in VIDEOS:
        if wanted and v["id"] not in wanted and v["id"].split("-")[0] not in wanted:
            continue
        with tempfile.TemporaryDirectory() as tmp:
            lengths[v["id"]] = build(v, tmp)
        if "thumb" in v:
            clip, name, lines = v["thumb"]
            thumbnail_png(os.path.join(OUT, v["id"] + "-thumbnail.png"), clip, moment(clip, name), lines)
    if not wanted:
        write_metadata(VIDEOS, lengths)


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(__file__))
    main()
