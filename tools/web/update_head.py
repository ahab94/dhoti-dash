#!/usr/bin/env python3
"""Injects tools/web/head.js into the Web export preset (html/head_include).

    python3 tools/web/update_head.py

Run it after editing head.js. It also embeds a 0.1 s silent WAV for the
old-iOS audio trick.
"""
import base64
import os
import re
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")


def silent_wav():
    n = 4410
    data = b"\x00\x00" * n
    return (b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVEfmt "
            + struct.pack("<IHHIIHH", 16, 1, 1, 44100, 88200, 2, 16)
            + b"data" + struct.pack("<I", len(data)) + data)


def main():
    js = open(os.path.join(HERE, "head.js")).read()
    js = js.replace("SILENT_WAV", "data:audio/wav;base64," + base64.b64encode(silent_wav()).decode())
    html = "<script>\n" + js + "</script>"
    value = html.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    path = os.path.join(ROOT, "export_presets.cfg")
    cfg = open(path).read()
    line = 'html/head_include="' + value + '"'
    if re.search(r'^html/head_include=".*"$', cfg, flags=re.M):
        cfg = re.sub(r'^html/head_include=".*"$', lambda _m: line, cfg, count=1, flags=re.M)
    else:
        cfg = cfg.replace("html/canvas_resize_policy=2", "html/canvas_resize_policy=2\n" + line, 1)
    open(path, "w").write(cfg)
    print("updated html/head_include (%d chars)" % len(html))


if __name__ == "__main__":
    main()
