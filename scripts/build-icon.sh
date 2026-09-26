#!/bin/sh
# Rasterize Assets/Logo/contour-icon.svg into PNGs and a macOS .icns.
# Also copies the .icns into the executable target, where it becomes the Dock icon.
# Uses only tools that ship with macOS: AppKit via `swift` (SVG render), sips, iconutil.
# (Not qlmanage: its thumbnails are flattened onto white, so the corners lose transparency.)
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
logo="$root/Assets/Logo"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

python3 "$root/scripts/generate-logo.py"

swift "$root/scripts/render-svg.swift" "$logo/contour-icon.svg" "$logo/contour-icon-1024.png" 1024

set_dir="$tmp/Contour.iconset"
mkdir "$set_dir"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$logo/contour-icon-1024.png" --out "$set_dir/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$logo/contour-icon-1024.png" --out "$set_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$set_dir" -o "$logo/Contour.icns"
cp "$logo/Contour.icns" "$root/Sources/Contour/Resources/AppIcon.icns"

echo "wrote $logo/contour-icon-1024.png, $logo/Contour.icns, and the bundled AppIcon.icns"
