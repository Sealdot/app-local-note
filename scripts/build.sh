#!/bin/sh
set -eu

mode="${1:-debug}"
output_dir="build/bin"
mkdir -p "$output_dir"

if [ "$mode" = "release" ]; then
  optimization="-O"
else
  optimization="-Onone"
fi

xcrun swiftc \
  "$optimization" \
  -module-name LocalNote \
  Sources/LocalNoteCore/*.swift \
  Sources/LocalNoteApp/*.swift \
  -framework AppKit \
  -framework SwiftUI \
  -framework Security \
  -framework Network \
  -o "$output_dir/LocalNote"

echo "Built $output_dir/LocalNote ($mode)"

