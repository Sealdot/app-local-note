#!/bin/sh
set -eu

"$(dirname "$0")/build.sh" release

app_dir="build/LocalNote.app"
contents_dir="$app_dir/Contents"
executable_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"

mkdir -p "$executable_dir" "$resources_dir"
cp "Resources/Info.plist" "$contents_dir/Info.plist"
cp "build/bin/LocalNote" "$executable_dir/LocalNote"
chmod 755 "$executable_dir/LocalNote"
codesign --force --deep --sign - "$app_dir"

echo "Packaged $app_dir"

