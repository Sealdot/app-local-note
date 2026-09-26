#!/bin/sh
set -eu

"$(dirname "$0")/verify.sh"

archive="build/LocalNote-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent build/LocalNote.app "$archive"
unzip -tq "$archive"
(cd build && shasum -a 256 LocalNote-macOS.zip > LocalNote-macOS.zip.sha256)

echo "Release archive: $archive"
echo "SHA-256: build/LocalNote-macOS.zip.sha256"
