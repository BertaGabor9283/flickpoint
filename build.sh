#!/usr/bin/env bash
# Builds Flickpoint.app with the Xcode command line tools (no Xcode project needed).
#
#   ./build.sh            build into build/Flickpoint.app
#   ./build.sh --dmg      build, then package build/Flickpoint.dmg (drag-to-Applications installer)
#   ./build.sh --install  build, copy to /Applications and open it
#
# Signing: ad-hoc by default. macOS may forget the Accessibility permission after
# each rebuild of an ad-hoc app. If you have an Apple Development certificate, sign with it
# so the permission sticks:  SIGN_ID="Apple Development: you@example.com" ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Flickpoint.app"
DMG="build/Flickpoint.dmg"
ARCH="$(uname -m)"
SIGN_ID="${SIGN_ID:--}"
MODE="${1:-}"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Swift compiler not found. Install the command line tools with: xcode-select --install" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling for ${ARCH}..."
xcrun swiftc -O -swift-version 5 -parse-as-library \
  -target "${ARCH}-apple-macos14.0" \
  -framework AppKit -framework SwiftUI -framework CoreMotion -framework Carbon -framework ApplicationServices -framework ServiceManagement \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/Flickpoint"

cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign "$SIGN_ID" "$APP"
echo "Built $APP"

if [ "$MODE" = "--dmg" ]; then
  STAGE="build/dmg-stage"
  rm -rf "$STAGE" "$DMG"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"   # drag the app onto this to install
  hdiutil create -volname "Flickpoint" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE"
  echo "Packaged $DMG"
  echo "Open it and drag Flickpoint onto Applications."
  open -R "$DMG"
fi

if [ "$MODE" = "--install" ]; then
  pkill -x Flickpoint 2>/dev/null || true
  rm -rf "/Applications/Flickpoint.app"
  cp -R "$APP" /Applications/
  open "/Applications/Flickpoint.app"
  echo "Installed to /Applications and launched."
fi
