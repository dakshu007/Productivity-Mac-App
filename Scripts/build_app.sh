#!/usr/bin/env bash
# Build FlowBreak.app for local development or as input to packaging.
#
#   Scripts/build_app.sh                 # release build for this Mac's architecture
#   Scripts/build_app.sh --universal     # arm64 + x86_64
#   Scripts/build_app.sh --debug         # debug configuration
#
# Output: build/FlowBreak.app (ad-hoc signed — fine for running on this Mac,
# NOT a notarized distribution build; see Scripts/sign_and_notarize.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="release"
UNIVERSAL=0
for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --debug) CONFIG="debug" ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: FlowBreak builds on macOS only (needs AppKit/SwiftUI and Xcode)." >&2
  exit 1
fi
for tool in swift codesign plutil; do
  command -v "$tool" >/dev/null || { echo "error: '$tool' not found. Install Xcode or the Command Line Tools." >&2; exit 1; }
done

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

ARCH_FLAGS=()
if [[ $UNIVERSAL -eq 1 ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> Building FlowBreak $VERSION ($BUILD_NUMBER), configuration: $CONFIG"
swift build -c "$CONFIG" "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}"
BIN_DIR="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}" --show-bin-path)"
BINARY="$BIN_DIR/FlowBreak"
[[ -x "$BINARY" ]] || { echo "error: built binary not found at $BINARY" >&2; exit 1; }

APP="$ROOT/build/FlowBreak.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/FlowBreak"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Ad-hoc signature so the app launches on Apple Silicon and keeps a stable
# identity for notifications. Distribution signing happens in sign_and_notarize.sh.
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"

echo "==> Architectures: $(lipo -archs "$APP/Contents/MacOS/FlowBreak")"
echo "==> Built $APP (ad-hoc signed, not notarized)"
echo "    Run it:  open \"$APP\""
