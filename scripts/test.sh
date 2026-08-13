#!/bin/sh
set -eu

output_dir="build/tests"
mkdir -p "$output_dir"

xcrun swiftc \
  -Onone \
  -module-name LocalNoteTests \
  Sources/LocalNoteCore/*.swift \
  Sources/LocalNoteTests/*.swift \
  -framework Security \
  -o "$output_dir/LocalNoteTests"

"$output_dir/LocalNoteTests" "$@"
