#!/usr/bin/env python3
"""Generate Contour's icon and logo lockup as SVG.

The mark is a set of nested topographic contour lines climbing to one highlighted peak:
the PR as terrain, mapped from the outside in, with a single point that deserves human
judgment. Each ring is a closed organic curve; inner rings drift toward the peak the way
real contours crowd toward a summit.

Writes into Assets/Logo/:
  contour-icon.svg    macOS app icon (1024x1024, Big Sur squircle grid)
  contour-logo.svg        horizontal lockup: mark + "Contour" wordmark, for light backgrounds
  contour-logo-dark.svg   the same lockup with a light wordmark, for dark backgrounds

The app draws the raw mark itself from a Swift port of `mark()`
(Sources/Contour/Views/Brand/ContourMark.swift); ContourMarkTests fails if the two drift,
so change both together.

Usage: python3 scripts/generate-logo.py
Raster/.icns output: scripts/build-icon.sh
"""
import math
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "Assets" / "Logo"

# Palette: deep ink ground, teal outer contours warming to an amber summit.
INK_TOP, INK_BOTTOM = "#16263D", "#0B1422"
LINE_OUTER, LINE_INNER = (0x3F, 0xC1, 0xC9), (0xFF, 0xC8, 0x57)
PEAK = "#FFC857"
# Wordmark on a dark page (e.g. GitHub's dark theme), where INK_TOP would vanish.
WORDMARK_ON_DARK = "#E6EDF3"

RINGS = 7


def lerp(a, b, t):
    return a + (b - a) * t


def hex_color(rgb):
    return "#%02X%02X%02X" % tuple(round(c) for c in rgb)


def ring_points(cx, cy, radius, level, n=180):
    """One organic closed contour. Harmonics shrink with level so the summit is rounder."""
    wobble = lerp(1.0, 0.45, level)
    pts = []
    for i in range(n):
        th = 2 * math.pi * i / n
        r = radius * (
            1
            + wobble * 0.16 * math.sin(th + 0.6)
            + wobble * 0.13 * math.sin(2 * th + 1.9 + level * 0.7)
            + wobble * 0.07 * math.sin(3 * th + 0.4 - level * 0.9)
            + wobble * 0.035 * math.sin(5 * th + 2.2 + level * 1.2)
        )
        pts.append((cx + r * math.cos(th), cy + r * math.sin(th) * 0.9))
    return pts


def smooth_path(pts):
    """Closed Catmull-Rom spline through pts, emitted as cubic Béziers."""
    n = len(pts)
    d = [f"M{pts[0][0]:.1f},{pts[0][1]:.1f}"]
    for i in range(n):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d.append(f"C{c1[0]:.1f},{c1[1]:.1f} {c2[0]:.1f},{c2[1]:.1f} {p2[0]:.1f},{p2[1]:.1f}")
    return "".join(d) + "Z"


def mark(cx, cy, scale, stroke):
    """Contour rings + peak marker centred near (cx, cy). scale = outer ring radius."""
    peak = (cx + scale * 0.24, cy - scale * 0.2)
    parts = []
    for k in range(RINGS):
        level = k / (RINGS - 1)
        # Rings step inward non-linearly so lines bunch up toward the summit (steep slope).
        radius = scale * lerp(1.0, 0.17, level ** 0.75)
        # Centres race toward the peak early, so the north-east slope is steep (lines
        # crowded) and the south-west slope is gentle (lines spread out).
        ccx = lerp(cx, peak[0], level ** 0.45)
        ccy = lerp(cy, peak[1], level ** 0.45)
        color = hex_color(tuple(lerp(a, b, level ** 1.4) for a, b in zip(LINE_OUTER, LINE_INNER)))
        opacity = lerp(0.55, 1.0, level)
        width = stroke * lerp(0.8, 1.15, level)
        parts.append(
            f'<path d="{smooth_path(ring_points(ccx, ccy, radius, level))}" fill="none" '
            f'stroke="{color}" stroke-opacity="{opacity:.2f}" stroke-width="{width:.1f}" '
            f'stroke-linejoin="round"/>'
        )
    pr = scale * 0.045
    parts.append(f'<circle cx="{peak[0]:.1f}" cy="{peak[1]:.1f}" r="{pr * 2.2:.1f}" fill="{PEAK}" fill-opacity="0.18"/>')
    parts.append(f'<circle cx="{peak[0]:.1f}" cy="{peak[1]:.1f}" r="{pr:.1f}" fill="{PEAK}"/>')
    return "\n    ".join(parts)


# Apple's macOS icon grid: 824pt body inset 100pt on a 1024 canvas, ~185 corner radius.
BODY_X, BODY_S, BODY_RX = 100, 824, 185


def tile(shadow):
    """The icon body in 1024-canvas coordinates: defs + artwork. Shared by icon and lockup."""
    x = y = BODY_X
    s, rx = BODY_S, BODY_RX
    shadow_attr = ' filter="url(#shadow)"' if shadow else ""
    return f"""<defs>
    <linearGradient id="ground" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{INK_TOP}"/>
      <stop offset="1" stop-color="{INK_BOTTOM}"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.6" cy="0.36" r="0.55">
      <stop offset="0" stop-color="{PEAK}" stop-opacity="0.16"/>
      <stop offset="1" stop-color="{PEAK}" stop-opacity="0"/>
    </radialGradient>
    <clipPath id="body"><rect x="{x}" y="{y}" width="{s}" height="{s}" rx="{rx}"/></clipPath>
    <filter id="shadow" x="-10%" y="-10%" width="120%" height="125%">
      <feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#000" flood-opacity="0.35"/>
    </filter>
  </defs>
  <rect x="{x}" y="{y}" width="{s}" height="{s}" rx="{rx}" fill="url(#ground)"{shadow_attr}/>
  <g clip-path="url(#body)">
    <rect x="{x}" y="{y}" width="{s}" height="{s}" fill="url(#glow)"/>
    {mark(470, 570, 520, 14)}
  </g>
  <rect x="{x + 1}" y="{y + 1}" width="{s - 2}" height="{s - 2}" rx="{rx - 1}" fill="none" stroke="#FFFFFF" stroke-opacity="0.08" stroke-width="2"/>"""


def icon_svg():
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  {tile(shadow=True)}
</svg>
"""


def logo_svg(wordmark=INK_TOP):
    # Tile scaled so its 824pt body becomes 280px, vertically centred in a 360px-tall lockup.
    k = 280 / BODY_S
    tx, ty = 40 - BODY_X * k, 40 - BODY_X * k
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1120" height="360" viewBox="0 0 1120 360">
  <g transform="translate({tx:.2f} {ty:.2f}) scale({k:.4f})">
  {tile(shadow=False)}
  </g>
  <text x="370" y="238" font-family="-apple-system, 'SF Pro Display', 'Helvetica Neue', Arial, sans-serif"
        font-size="176" font-weight="600" letter-spacing="-4" fill="{wordmark}">Contour</text>
</svg>
"""


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "contour-icon.svg").write_text(icon_svg())
    (OUT / "contour-logo.svg").write_text(logo_svg())
    (OUT / "contour-logo-dark.svg").write_text(logo_svg(wordmark=WORDMARK_ON_DARK))
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
