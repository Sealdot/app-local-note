#!/bin/sh
set -eu

output_dir="${1:-build/theme-qa}"
mkdir -p "$output_dir"

xcrun swiftc \
  -Onone \
  -module-name LocalNoteThemePreview \
  Sources/LocalNoteCore/*.swift \
  Sources/LocalNoteApp/Appearance.swift \
  Sources/LocalNoteApp/AppModel.swift \
  Sources/LocalNoteApp/ApplicationMenu.swift \
  Sources/LocalNoteApp/ContentView.swift \
  scripts/ThemePreview.swift \
  -framework AppKit \
  -framework SwiftUI \
  -framework Network \
  -framework Security \
  -o "$output_dir/ThemePreview"

"$output_dir/ThemePreview" "$output_dir"
