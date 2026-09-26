#!/bin/sh
set -eu

mode="${1:-debug}"
output_dir="build/bin"
mkdir -p "$output_dir"

compile() {
  target="$1"
  output="$2"
  optimization="$3"

  if [ -n "$target" ]; then
    xcrun swiftc -target "$target" "$optimization" \
      -module-name LocalNote \
      Sources/LocalNoteCore/*.swift \
      Sources/LocalNoteApp/*.swift \
      -framework AppKit -framework SwiftUI -framework Security -framework Network \
      -o "$output"
  else
    xcrun swiftc "$optimization" \
      -module-name LocalNote \
      Sources/LocalNoteCore/*.swift \
      Sources/LocalNoteApp/*.swift \
      -framework AppKit -framework SwiftUI -framework Security -framework Network \
      -o "$output"
  fi
}

if [ "$mode" = "release" ]; then
  compile arm64-apple-macos11.0 "$output_dir/LocalNote-arm64" -O
  compile x86_64-apple-macos11.0 "$output_dir/LocalNote-x86_64" -O
  xcrun lipo -create \
    "$output_dir/LocalNote-arm64" \
    "$output_dir/LocalNote-x86_64" \
    -output "$output_dir/LocalNote"
else
  compile "" "$output_dir/LocalNote" -Onone
fi

echo "Built $output_dir/LocalNote ($mode)"
