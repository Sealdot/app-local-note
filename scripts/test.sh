#!/bin/sh
set -eu

output_dir="build/tests"
mkdir -p "$output_dir"

xcrun swiftc \
  -Onone \
  -DLOCAL_NOTE_DIRECT_TESTS \
  -module-name LocalNoteTests \
  Sources/LocalNoteCore/*.swift \
  Sources/LocalNoteApp/AppModel.swift \
  Sources/LocalNoteApp/ApplicationMenu.swift \
  Sources/LocalNoteApp/ContentView.swift \
  Sources/LocalNoteTests/*.swift \
  -framework AppKit \
  -framework SwiftUI \
  -framework Network \
  -framework Security \
  -o "$output_dir/LocalNoteTests"

"$output_dir/LocalNoteTests" "$@"
