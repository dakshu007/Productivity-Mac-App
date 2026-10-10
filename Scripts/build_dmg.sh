#!/usr/bin/env bash
# Package build/FlowBreak.app into a DMG with an /Applications shortcut.
#
#   Scripts/build_dmg.sh            # packages the existing build/FlowBreak.app
#   Scripts/build_dmg.sh --build    # runs build_universal.sh first
#
# Without Developer ID signing this produces a DEVELOPMENT DMG: the app inside is
# ad-hoc signed and not notarized, and the output name says so. For a public
# release use Scripts/sign_and_notarize.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "${1:-}" == "--build" ]]; then
  "$ROOT/Scripts/build_universal.sh"
fi

[[ "$(uname -s)" == "Darwin" ]] || { echo "error: hdiutil requires macOS." >&2; exit 1; }
command -v hdiutil >/dev/null || { echo "error: hdiutil not found." >&2; exit 1; }

APP="$ROOT/build/FlowBreak.app"
[[ -d "$APP" ]] || { echo "error: $APP not found. Run Scripts/build_app.sh first (or pass --build)." >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/FlowBreak")"

# Is the app signed with a Developer ID? (ad-hoc signatures report "Signature=adhoc")
if codesign -dv "$APP" 2>&1 | grep -q "Authority=Developer ID Application"; then
  SIGNING="Developer ID signed"
  SUFFIX="${DMG_SUFFIX:-}"
else
  SIGNING="ad-hoc signed, NOT notarized (development build)"
  SUFFIX="${DMG_SUFFIX:--unsigned}"
  echo "warning: packaging an app that is not Developer ID signed." >&2
  echo "warning: the DMG is named *-unsigned and Gatekeeper will ask the user to approve it." >&2
fi

OUT_DIR="$ROOT/build/dmg"
STAGE="$OUT_DIR/stage"
DMG="$OUT_DIR/FlowBreak-$VERSION$SUFFIX.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"

ditto "$APP" "$STAGE/FlowBreak.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Install FlowBreak.txt" <<TXT
FlowBreak $VERSION (build $BUILD)
Architectures: $ARCHS
Signing: $SIGNING
Requires macOS 13 Ventura or later.

INSTALL
1. Drag FlowBreak into the Applications folder in this window.
2. Eject this disk image.
3. Open FlowBreak from Applications. It lives in the menu bar (top-right of
   your screen) — look for the leaf-and-circle icon. There is no Dock icon
   unless you turn it on in Settings.

FIRST LAUNCH OF A DEVELOPMENT BUILD
This build is not notarized by Apple, so macOS blocks the first launch:
  - macOS 15 Sequoia and later: try to open FlowBreak once, then go to
    System Settings > Privacy & Security, scroll down and click "Open Anyway".
  - macOS 13-14: Control-click FlowBreak in Applications, choose Open, then Open.
  - Or in Terminal:  xattr -dr com.apple.quarantine /Applications/FlowBreak.app

PRIVACY
FlowBreak stores everything locally on your Mac. No account, no cloud, no analytics.
App usage tracking is off unless you turn it on.
TXT

hdiutil create \
  -volname "FlowBreak $VERSION" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov "$DMG" >/dev/null
rm -rf "$STAGE"

hdiutil verify "$DMG" >/dev/null
( cd "$OUT_DIR" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256" )

echo "==> DMG:      $DMG"
echo "==> SHA-256:  $(cut -d' ' -f1 "$DMG.sha256")"
echo "==> Signing:  $SIGNING"
echo "Next: open the DMG and drag FlowBreak to Applications."
