#!/bin/sh
set -eu

source_icon="Resources/Brand/AppIcon-1024.png"
iconset="Resources/AppIcon.iconset"
output="Resources/AppIcon.icns"

if [ ! -s "$source_icon" ]; then
  echo "Missing $source_icon" >&2
  exit 1
fi

mkdir -p "$iconset"
sips -z 16 16 "$source_icon" --out "$iconset/icon_16x16.png" >/dev/null
sips -z 32 32 "$source_icon" --out "$iconset/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$source_icon" --out "$iconset/icon_32x32.png" >/dev/null
sips -z 64 64 "$source_icon" --out "$iconset/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$source_icon" --out "$iconset/icon_128x128.png" >/dev/null
sips -z 256 256 "$source_icon" --out "$iconset/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$source_icon" --out "$iconset/icon_256x256.png" >/dev/null
sips -z 512 512 "$source_icon" --out "$iconset/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$source_icon" --out "$iconset/icon_512x512.png" >/dev/null
cp "$source_icon" "$iconset/icon_512x512@2x.png"
iconutil -c icns "$iconset" -o "$output"

echo "Generated $output"

