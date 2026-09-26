#!/bin/sh
# Rasterize Assets/Logo/contour-icon.svg into PNGs and a macOS .icns.
# Uses only tools that ship with macOS: qlmanage (WebKit SVG render), sips, iconutil.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
logo="$root/Assets/Logo"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

python3 "$root/scripts/generate-logo.py"

qlmanage -t -s 1024 -o "$tmp" "$logo/contour-icon.svg" >/dev/null 2>&1
cp "$tmp/contour-icon.svg.png" "$logo/contour-icon-1024.png"

set_dir="$tmp/Contour.iconset"
mkdir "$set_dir"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$logo/contour-icon-1024.png" --out "$set_dir/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$logo/contour-icon-1024.png" --out "$set_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$set_dir" -o "$logo/Contour.icns"

echo "wrote $logo/contour-icon-1024.png and $logo/Contour.icns"
