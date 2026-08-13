#!/bin/sh
set -eu

"$(dirname "$0")/test.sh"
"$(dirname "$0")/build.sh" release
"$(dirname "$0")/package-app.sh"

plutil -lint build/LocalNote.app/Contents/Info.plist
codesign --verify --deep --strict build/LocalNote.app

if [ ! -s "build/LocalNote.app/Contents/Resources/AppIcon.icns" ]; then
  echo "Packaged app icon is missing" >&2
  exit 1
fi

if [ "$(plutil -extract CFBundleIconFile raw build/LocalNote.app/Contents/Info.plist)" != "AppIcon" ]; then
  echo "Packaged app must reference AppIcon.icns" >&2
  exit 1
fi

if [ "$(plutil -extract LSUIElement raw build/LocalNote.app/Contents/Info.plist)" != "true" ]; then
  echo "Packaged app must be a menu bar LSUIElement" >&2
  exit 1
fi

if rg -n --hidden \
  -g '!build/**' \
  -g '!.git/**' \
  '(ntn_[A-Za-z0-9]{20,}|secret_[A-Za-z0-9]{20,}|gh[opsu]_[A-Za-z0-9]{20,})' .; then
  echo "Potential credential found in source tree" >&2
  exit 1
fi

echo "Verification passed"

