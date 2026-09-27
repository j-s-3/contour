#!/usr/bin/env python3
"""Generate the website's favicon and Open Graph card from the logo generator.

Writes into site/:
  favicon.svg          the app icon tile, with fewer spline points so it stays small
  .build/og.html       1200x630 social card source (rendered to assets/og.png by Chrome)

Rasters (assets/favicon-32.png, assets/apple-touch-icon.png, assets/og.png):
  swift scripts/render-svg.swift site/favicon.svg site/assets/apple-touch-icon.png 180
  swift scripts/render-svg.swift site/favicon.svg site/assets/favicon-32.png 32
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new \
      --hide-scrollbars --window-size=1200,630 --screenshot=site/assets/og.png .build/og.html

Usage: python3 scripts/generate-site-art.py
"""
import importlib.util
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # importing generate-logo.py would otherwise leave a __pycache__

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"

spec = importlib.util.spec_from_file_location("logo", ROOT / "scripts" / "generate-logo.py")
logo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(logo)

# 48 points per ring is indistinguishable at favicon sizes and ~4x smaller than the app icon.
logo.ring_points.__defaults__ = (48,)


def favicon_svg():
    # Crop the 1024 canvas to the icon body so the tile fills the tab.
    return logo.icon_svg().replace('viewBox="0 0 1024 1024"', 'viewBox="96 96 832 840"')


def og_html():
    tile = logo.tile(shadow=False)
    return f"""<!doctype html>
<meta charset="utf-8">
<style>
  html, body {{ margin: 0; width: 1200px; height: 630px; background: #070b12; overflow: hidden; }}
  body {{ display: flex; align-items: center; gap: 64px; padding: 0 96px; box-sizing: border-box;
         font-family: -apple-system, "SF Pro Display", "Helvetica Neue", sans-serif; color: #e8eef6;
         background: radial-gradient(900px 520px at 20% 40%, #13233a 0%, #070b12 70%); }}
  svg {{ width: 300px; height: 300px; flex: none; }}
  p {{ margin: 0; }}
  .w {{ font: 600 22px/1 ui-monospace, "SF Mono", Menlo, monospace; letter-spacing: .45em; color: #8d9bb0;
        text-transform: uppercase; margin-bottom: 30px; }}
  h1 {{ margin: 0; font-size: 76px; line-height: 1; letter-spacing: -.045em; font-weight: 700; }}
  h1 span {{ color: #ffc857; }}
  .s {{ margin-top: 28px; font-size: 26px; color: #8d9bb0; letter-spacing: -.01em; }}
</style>
<svg viewBox="96 96 832 840">{tile}</svg>
<div>
  <p class="w">Contour</p>
  <h1>Understand the change.<br><span>Not just the diff.</span></h1>
  <p class="s">Pull request review for code an AI helped write.</p>
</div>
"""


def main():
    (SITE / "assets").mkdir(parents=True, exist_ok=True)
    (SITE / "favicon.svg").write_text(favicon_svg())
    (ROOT / ".build").mkdir(exist_ok=True)
    (ROOT / ".build" / "og.html").write_text(og_html())
    print(f"wrote {SITE}")


if __name__ == "__main__":
    main()
