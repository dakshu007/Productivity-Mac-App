#!/usr/bin/env python3
"""Render FlowBreak brand assets from one geometric definition.

Outputs (all committed to the repo so the build does not depend on Python):
  Design/FlowBreakLogo.svg          vector source of the symbol
  Design/AppIcon.svg                vector source of the app icon
  Design/AppIcon-1024.png           1024x1024 app icon master
  Design/MenuBarTemplate.png        monochrome template preview (36x36 @2x)
  Design/BrandPreview.png           light/dark/monochrome preview sheet
  Resources/AppIcon.icns            macOS icon container (PNG-encoded entries)

The same geometry is reproduced in Swift (Sources/FlowBreak/DesignSystem/LogoShape.swift)
so the in-app logo and menu-bar template match these files.

Usage: python3 Scripts/generate_icons.py   (requires Pillow)
"""
import io
import math
import os
import struct

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AMBER = (255, 186, 48)
INK = (25, 27, 24)
INK_TOP = (44, 46, 40)
OFFWHITE = (251, 250, 243)
NEUTRAL = (106, 106, 95)

# ---------------------------------------------------------------------------
# Geometry, in a unit square (0..1). Shared with LogoShape.swift.
#   Ring: open circle (the "flow"), centre (0.5, 0.5), radius 0.34, stroke 0.105,
#         gap centred at -45 deg (top-right), gap width 62 deg.
#   Leaf: lens shape on an axis from BASE to TIP, pointing to the top-right,
#         its tip leaving the ring through the gap.
# ---------------------------------------------------------------------------
RING_R = 0.34
RING_W = 0.105
GAP_CENTER = -45.0   # degrees, screen coordinates (y down) => top-right
GAP = 62.0
BASE = (0.35, 0.65)
TIP = (0.85, 0.15)
LEAF_W = 0.25        # maximum leaf width as fraction of unit
MIDRIB_W = 0.032
MIDRIB_FROM, MIDRIB_TO = 0.16, 0.60
STEM_LEN = 0.05      # stem continues the leaf axis behind the base
STEM_W = 0.055


def leaf_points(n=96):
    bx, by = BASE
    tx, ty = TIP
    length = math.hypot(tx - bx, ty - by)
    ux, uy = (tx - bx) / length, (ty - by) / length
    nx, ny = -uy, ux
    pts_a, pts_b = [], []
    for i in range(n + 1):
        t = i / n
        # Asymmetric lens: fuller near the base, sharp tip.
        half = (LEAF_W / 2) * math.sin(math.pi * t) ** 0.9 * (1.12 - 0.24 * t)
        cx, cy = bx + ux * length * t, by + uy * length * t
        pts_a.append((cx + nx * half, cy + ny * half))
        pts_b.append((cx - nx * half, cy - ny * half))
    return pts_a + list(reversed(pts_b))


def midrib_segment():
    bx, by = BASE
    tx, ty = TIP
    return ((bx + (tx - bx) * MIDRIB_FROM, by + (ty - by) * MIDRIB_FROM),
            (bx + (tx - bx) * MIDRIB_TO, by + (ty - by) * MIDRIB_TO))


def stem_segment():
    bx, by = BASE
    tx, ty = TIP
    length = math.hypot(tx - bx, ty - by)
    ux, uy = (tx - bx) / length, (ty - by) / length
    return ((bx - ux * STEM_LEN, by - uy * STEM_LEN), (bx + ux * 0.04, by + uy * 0.04))


def ring_arc_points(n=180, radius=RING_R):
    start = GAP_CENTER + GAP / 2
    sweep = 360 - GAP
    pts = []
    for i in range(n + 1):
        a = math.radians(start + sweep * i / n)
        pts.append((0.5 + radius * math.cos(a), 0.5 + radius * math.sin(a)))
    return pts


def draw_symbol(draw, origin, size, color, cutout_color=None, midrib=True):
    ox, oy = origin

    def P(p):
        return (ox + p[0] * size, oy + p[1] * size)

    # Ring as a filled annulus sector with round caps.
    outer = [P(p) for p in ring_arc_points(radius=RING_R + RING_W / 2)]
    inner = [P(p) for p in ring_arc_points(radius=RING_R - RING_W / 2)]
    draw.polygon(outer + list(reversed(inner)), fill=color)
    w = RING_W * size
    centre_line = [P(p) for p in ring_arc_points()]
    for end in (centre_line[0], centre_line[-1]):
        r = w / 2
        draw.ellipse([end[0] - r, end[1] - r, end[0] + r, end[1] + r], fill=color)
    # Stem behind the leaf base.
    (sa, sb) = stem_segment()
    sw = STEM_W * size
    draw.line([P(sa), P(sb)], fill=color, width=int(round(sw)))
    r = sw / 2
    e = P(sa)
    draw.ellipse([e[0] - r, e[1] - r, e[0] + r, e[1] + r], fill=color)
    draw.polygon([P(p) for p in leaf_points()], fill=color)
    if midrib and cutout_color is not None:
        a, b = midrib_segment()
        mw = MIDRIB_W * size
        draw.line([P(a), P(b)], fill=cutout_color, width=max(1, int(round(mw))))
        for end in (P(a),):
            r = mw / 2
            draw.ellipse([end[0] - r, end[1] - r, end[0] + r, end[1] + r], fill=cutout_color)


def squircle_mask(size, inset, radius_frac=0.2237):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    box = [inset, inset, size - inset, size - inset]
    d.rounded_rectangle(box, radius=int((size - 2 * inset) * radius_frac), fill=255)
    return m


def render_app_icon(px=1024, ss=4):
    S = px * ss
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # Apple's macOS icon grid: 824/1024 body with ~100px margin.
    inset = int(S * 100 / 1024)
    bg = Image.new("RGBA", (S, S), INK + (255,))
    grad = ImageDraw.Draw(bg)
    for y in range(S):  # very gentle vertical warmth, survives at small sizes
        t = y / S
        c = tuple(int(INK_TOP[i] * (1 - t) + INK[i] * t) for i in range(3))
        grad.line([(0, y), (S, y)], fill=c + (255,))
    img.paste(bg, (0, 0), squircle_mask(S, inset))
    d = ImageDraw.Draw(img)
    body = S - 2 * inset
    sym = body * 0.80
    off = inset + (body - sym) / 2
    draw_symbol(d, (off, off), sym, AMBER + (255,), cutout_color=None, midrib=False)
    # midrib + halo drawn after ring with the background colour
    draw_symbol_detail(d, (off, off), sym, INK + (255,))
    return img.resize((px, px), Image.LANCZOS)


def draw_symbol_detail(draw, origin, size, cut):
    ox, oy = origin

    def P(p):
        return (ox + p[0] * size, oy + p[1] * size)

    a, b = midrib_segment()
    mw = MIDRIB_W * size
    draw.line([P(a), P(b)], fill=cut, width=max(1, int(round(mw))))
    r = mw / 2
    for e in (P(b),):
        draw.ellipse([e[0] - r, e[1] - r, e[0] + r, e[1] + r], fill=cut)


def render_symbol(px, color, bg=None, ss=4, midrib=True):
    S = px * ss
    img = Image.new("RGBA", (S, S), (bg + (255,)) if bg else (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    draw_symbol(d, (0, 0), S, color + (255,), midrib=False)
    if midrib:
        cut = (bg + (255,)) if bg else (0, 0, 0, 0)
        draw_symbol_detail(d, (0, 0), S, cut)
    return img.resize((px, px), Image.LANCZOS)


def write_icns(master, path):
    # Modern icns: entries hold PNG data. Types per Apple's IconFamily spec.
    entries = [
        (b"icp4", 16), (b"icp5", 32), (b"icp6", 64),
        (b"ic07", 128), (b"ic08", 256), (b"ic09", 512), (b"ic10", 1024),
        (b"ic11", 32), (b"ic12", 64), (b"ic13", 256), (b"ic14", 512),
    ]
    chunks = b""
    for ostype, size in entries:
        buf = io.BytesIO()
        master.resize((size, size), Image.LANCZOS).save(buf, format="PNG")
        data = buf.getvalue()
        chunks += ostype + struct.pack(">I", len(data) + 8) + data
    with open(path, "wb") as f:
        f.write(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)


def svg_path(points, scale):
    return "M" + " L".join(f"{x * scale:.2f},{y * scale:.2f}" for x, y in points) + " Z"


def write_svgs():
    s = 1024
    ring = ring_arc_points(90)
    ring_d = "M" + " L".join(f"{x * s:.2f},{y * s:.2f}" for x, y in ring)
    leaf_d = svg_path(leaf_points(64), s)
    (ax, ay), (bx, by) = midrib_segment()
    (sax, say), (sbx, sby) = stem_segment()
    symbol = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <title>FlowBreak symbol</title>
  <path d="{ring_d}" fill="none" stroke="#FFBA30" stroke-width="{RING_W * s:.1f}" stroke-linecap="round" stroke-linejoin="round"/>
  <line x1="{sax * s:.1f}" y1="{say * s:.1f}" x2="{sbx * s:.1f}" y2="{sby * s:.1f}" stroke="#FFBA30" stroke-width="{STEM_W * s:.1f}" stroke-linecap="round"/>
  <path d="{leaf_d}" fill="#FFBA30"/>
  <line x1="{ax * s:.1f}" y1="{ay * s:.1f}" x2="{bx * s:.1f}" y2="{by * s:.1f}" stroke="#191B18" stroke-width="{MIDRIB_W * s:.1f}" stroke-linecap="round"/>
</svg>
'''
    with open(os.path.join(ROOT, "Design", "FlowBreakLogo.svg"), "w") as f:
        f.write(symbol)

    # App icon: body 824 at 100 inset, symbol 80% of body centred.
    body = 824
    sym = body * 0.80
    off = 100 + (body - sym) / 2

    def T(p):
        return (off + p[0] * sym, off + p[1] * sym)

    ring_i = "M" + " L".join(f"{T(p)[0]:.2f},{T(p)[1]:.2f}" for p in ring)
    leaf_i = "M" + " L".join(f"{T(p)[0]:.2f},{T(p)[1]:.2f}" for p in leaf_points(64)) + " Z"
    a, b = (T(p) for p in midrib_segment())
    sa, sb = (T(p) for p in stem_segment())
    icon = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <title>FlowBreak app icon</title>
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#2C2E28"/>
      <stop offset="1" stop-color="#191B18"/>
    </linearGradient>
  </defs>
  <rect x="100" y="100" width="824" height="824" rx="184" fill="url(#bg)"/>
  <path d="{ring_i}" fill="none" stroke="#FFBA30" stroke-width="{RING_W * sym:.1f}" stroke-linecap="round" stroke-linejoin="round"/>
  <line x1="{sa[0]:.1f}" y1="{sa[1]:.1f}" x2="{sb[0]:.1f}" y2="{sb[1]:.1f}" stroke="#FFBA30" stroke-width="{STEM_W * sym:.1f}" stroke-linecap="round"/>
  <path d="{leaf_i}" fill="#FFBA30"/>
  <line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" stroke="#191B18" stroke-width="{MIDRIB_W * sym:.1f}" stroke-linecap="round"/>
</svg>
'''
    with open(os.path.join(ROOT, "Design", "AppIcon.svg"), "w") as f:
        f.write(icon)


def preview_sheet(icon):
    W, H = 1500, 620
    sheet = Image.new("RGBA", (W, H), OFFWHITE + (255,))
    d = ImageDraw.Draw(sheet)
    d.rectangle([W // 2, 0, W, H], fill=INK + (255,))
    for half, bg, fg in ((0, OFFWHITE, INK), (1, INK, OFFWHITE)):
        x0 = half * W // 2 + 40
        sheet.alpha_composite(icon.resize((256, 256), Image.LANCZOS), (x0, 40))
        x = x0 + 290
        for sz in (128, 64, 32, 16):
            ic = icon.resize((sz, sz), Image.LANCZOS)
            sheet.alpha_composite(ic, (x, 40 + (128 - sz)))
            x += sz + 24
        # symbol in accent, in monochrome (template), at menu-bar sizes
        sheet.alpha_composite(render_symbol(160, AMBER, bg=bg), (x0, 340))
        sheet.alpha_composite(render_symbol(160, fg, bg=bg), (x0 + 200, 340))
        mx = x0 + 400
        for sz in (44, 36, 22, 18, 16):
            sheet.alpha_composite(render_symbol(sz, fg, bg=bg, midrib=sz >= 32), (mx, 420 + (44 - sz)))
            mx += sz + 22
    sheet.save(os.path.join(ROOT, "Design", "BrandPreview.png"))


def main():
    os.makedirs(os.path.join(ROOT, "Design"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "Resources"), exist_ok=True)
    icon = render_app_icon()
    icon.save(os.path.join(ROOT, "Design", "AppIcon-1024.png"))
    write_icns(icon, os.path.join(ROOT, "Resources", "AppIcon.icns"))
    render_symbol(36, (0, 0, 0), midrib=False).save(os.path.join(ROOT, "Design", "MenuBarTemplate.png"))
    write_svgs()
    preview_sheet(icon)
    print("Wrote Design/* and Resources/AppIcon.icns")


if __name__ == "__main__":
    main()
