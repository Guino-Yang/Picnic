#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

# Package the generated artwork at all standard macOS icon resolutions.
# sips only downsamples here; the artwork and transparency are preserved.
ICON_SOURCE="Assets/Picnic-icon.png"
ICONSET="build/Picnic.iconset"
test -f "$ICON_SOURCE"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Assets/Picnic.icns
