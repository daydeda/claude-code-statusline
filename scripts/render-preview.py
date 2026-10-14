#!/usr/bin/env python3
"""Render the README previews from the real statusline.sh output.

    python3 scripts/render-preview.py

Writes images/preview.svg (animated: rainbow effort + pulsing limit) and
images/themes.svg (every theme). Re-run after changing statusline.sh.
"""
import json
import os
import re
import subprocess
import tempfile
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "statusline.sh"
OUT = ROOT / "images"

NOW = 1791993600  # Wed 14 Oct 2026 16:00 UTC: a fixed clock keeps output stable
FONT = "ui-monospace, SFMono-Regular, Menlo, Consolas, 'Liberation Mono', monospace"
FONT_SIZE, LINE_H, CHAR_W, PAD = 14, 21, 8.45, 22

THEMES = {  # name: (background, default text)
    "default": ("#0d1117", "#c9d1d9"),
    "catppuccin": ("#1e1e2e", "#cdd6f4"),
    "dracula": ("#282a36", "#f8f8f2"),
    "nord": ("#2e3440", "#d8dee9"),
    "gruvbox": ("#282828", "#ebdbb2"),
    "tokyonight": ("#1a1b26", "#c0caf5"),
}


def sample(cwd, effort, five, seven):
    return json.dumps({
        "model": {"display_name": "Opus 5.5"},
        "thinking": {"enabled": True},
        "effort": {"level": effort},
        "workspace": {"current_dir": cwd},
        "context_window": {"used_percentage": 46},
        "cost": {"total_lines_added": 248, "total_lines_removed": 31,
                 "total_duration_ms": 2530000, "total_cost_usd": 3.87},
        "rate_limits": {
            "five_hour": {"used_percentage": five, "resets_at": NOW + 4230},
            "seven_day": {"used_percentage": seven, "resets_at": NOW + 198630},
        },
    })


def run(payload, now, **env):
    full = dict(os.environ, TZ="UTC", STATUSLINE_CONFIG="/nonexistent",
                STATUSLINE_CLOCK_OVERRIDE=str(now), **env)
    return subprocess.run(["bash", str(SCRIPT)], input=payload, env=full,
                          capture_output=True, text=True, check=True).stdout


SGR = re.compile(r"\x1b\[([0-9;]*)m")


def parse(line, default_fg):
    """Split one ANSI line into (text, fill, bold, italic, dim) spans."""
    spans, pos = [], 0
    style = dict(fill=default_fg, bold=False, italic=False, dim=False)
    for m in SGR.finditer(line):
        if m.start() > pos:
            spans.append((line[pos:m.start()], dict(style)))
        codes = [int(c) for c in m.group(1).split(";") if c] or [0]
        i = 0
        while i < len(codes):
            c = codes[i]
            if c == 0:
                style = dict(fill=default_fg, bold=False, italic=False, dim=False)
            elif c == 1:
                style["bold"] = True
            elif c == 2:
                style["dim"] = True
            elif c == 3:
                style["italic"] = True
            elif c in (38, 48) and codes[i + 1:i + 2] == [2]:
                if c == 38:
                    style["fill"] = "#%02x%02x%02x" % tuple(codes[i + 2:i + 5])
                i += 4
            i += 1
        pos = m.end()
    if pos < len(line):
        spans.append((line[pos:], dict(style)))
    return spans


def text_lines(output, default_fg, x, y):
    parts = []
    for n, line in enumerate(output.split("\n")):
        tspans = []
        for text, s in parse(line, default_fg):
            attrs = 'fill="%s"' % s["fill"]
            if s["bold"]:
                attrs += ' font-weight="700"'
            if s["italic"]:
                attrs += ' font-style="italic"'
            if s["dim"]:
                attrs += ' fill-opacity="0.4"'
            tspans.append("<tspan %s>%s</tspan>" % (attrs, escape(text)))
        parts.append('<text x="%d" y="%d" xml:space="preserve">%s</text>'
                     % (x, y + n * LINE_H, "".join(tspans)))
    return "\n".join(parts)


def width_of(outputs):
    longest = max(len(SGR.sub("", l)) for o in outputs for l in o.split("\n"))
    return int(longest * CHAR_W + PAD * 2)


def svg(width, height, body, style=""):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
            'viewBox="0 0 %d %d" font-family="%s" font-size="%d">\n%s%s\n</svg>\n'
            % (width, height, width, height, FONT, FONT_SIZE,
               "<style>%s</style>\n" % style if style else "", body))


def window(width, height, bg):
    return ('<rect width="%d" height="%d" rx="10" fill="%s"/>\n'
            '<circle cx="20" cy="18" r="6" fill="#ff5f57"/>'
            '<circle cx="40" cy="18" r="6" fill="#febc2e"/>'
            '<circle cx="60" cy="18" r="6" fill="#28c840"/>\n' % (width, height, bg))


def hero(cwd):
    """14 one-second frames: the rainbow cycles (7 colors) and the 92% limit
    pulses (2 states), so 14 frames loop seamlessly."""
    bg, fg = THEMES["default"]
    frames = [run(sample(cwd, "max", 92, 41), NOW + i) for i in range(14)]
    w, h = width_of(frames), 44 + 4 * LINE_H + 12
    style = ("g.f{visibility:hidden;animation:show 14s step-end infinite}"
             "@keyframes show{0%{visibility:visible}7.142857%{visibility:hidden}"
             "100%{visibility:hidden}}")
    body = window(w, h, bg)
    for i, out in enumerate(frames):
        body += '<g class="f" style="animation-delay:%ds">\n%s\n</g>\n' % (
            i - 14, text_lines(out, fg, PAD, 56))
    return svg(w, h, body, style)


def themes(cwd):
    outs = {name: run(sample(cwd, "xhigh", 67, 23), NOW, STATUSLINE_THEME=name,
                      STATUSLINE_ANIMATE="0") for name in THEMES}
    w = width_of(list(outs.values()))
    panel_h = 30 + 4 * LINE_H + 14
    body = ""
    for n, (name, out) in enumerate(outs.items()):
        bg, fg = THEMES[name]
        y = n * (panel_h + 12)
        body += '<rect y="%d" width="%d" height="%d" rx="10" fill="%s"/>\n' % (y, w, panel_h, bg)
        body += ('<text x="%d" y="%d" fill="%s" opacity="0.6" font-size="12">'
                 'STATUSLINE_THEME=%s</text>\n' % (PAD, y + 22, fg, name))
        body += text_lines(out, fg, PAD, y + 48) + "\n"
    return svg(w, len(outs) * (panel_h + 12) - 12, body)


def main():
    OUT.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        cwd = os.path.join(tmp, "my-app")
        os.mkdir(cwd)
        git = ["git", "-C", cwd, "-c", "user.name=preview", "-c", "user.email=preview@example.com"]
        subprocess.run(["git", "init", "-q", "-b", "main", cwd], check=True)
        Path(cwd, "app.ts").write_text("".join("line %d\n" % i for i in range(10)))
        Path(cwd, "auth.ts").write_text("".join("line %d\n" % i for i in range(8)))
        subprocess.run(git + ["add", "-A"], check=True)
        subprocess.run(git + ["commit", "-qm", "init"], check=True)
        # Uncommitted work: "● 3 changes +40 -5"
        Path(cwd, "app.ts").write_text("".join("line %d\n" % i for i in range(3, 10))
                                       + "".join("new %d\n" % i for i in range(30)))
        Path(cwd, "auth.ts").write_text("".join("line %d\n" % i for i in range(6))
                                        + "".join("new %d\n" % i for i in range(10)))
        Path(cwd, "README.md").write_text("x\n")
        (OUT / "preview.svg").write_text(hero(cwd))
        (OUT / "themes.svg").write_text(themes(cwd))
    print("wrote images/preview.svg and images/themes.svg")


if __name__ == "__main__":
    main()
