#!/bin/sh
set -eu

output_dir="${1:-build/readme-media}"
mkdir -p "$output_dir"

xcrun swiftc \
  -Onone \
  -module-name LocalNoteReadmePreview \
  Sources/LocalNoteCore/*.swift \
  Sources/LocalNoteApp/Appearance.swift \
  Sources/LocalNoteApp/AppModel.swift \
  Sources/LocalNoteApp/ApplicationMenu.swift \
  Sources/LocalNoteApp/ContentView.swift \
  scripts/ReadmePreview.swift \
  -framework AppKit \
  -framework SwiftUI \
  -framework Network \
  -framework Security \
  -o "$output_dir/ReadmePreview"

"$output_dir/ReadmePreview" "$output_dir"
