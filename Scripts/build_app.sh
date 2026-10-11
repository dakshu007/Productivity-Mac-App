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

# App Intents metadata (Shortcuts/Siri/Spotlight). SwiftPM doesn't run Apple's
# extractor after compiling an executable, so we run it here on the compiler's
# constant-value output. macOS reads Contents/Resources/Metadata.appintents.
CONST_VALUES="$(find "$ROOT/.build" -path "*/Release/FlowBreak.build/Objects-normal/arm64/FlowBreak-master.swiftconstvalues" 2>/dev/null | head -n1 || true)"
[[ -n "$CONST_VALUES" ]] || CONST_VALUES="$(find "$ROOT/.build" -path "*FlowBreak.build/Objects-normal/*/FlowBreak-master.swiftconstvalues" 2>/dev/null | head -n1 || true)"
if [[ -n "$CONST_VALUES" ]] && xcrun --find appintentsmetadataprocessor >/dev/null 2>&1; then
  WORK="$(mktemp -d)"
  find "$ROOT/Sources/FlowBreak" -name "*.swift" | sort > "$WORK/sources.list"
  echo "$CONST_VALUES" > "$WORK/constvalues.list"
  PROCESSOR="$(xcrun --find appintentsmetadataprocessor)"
  TOOLCHAIN_DIR="$(cd "$(dirname "$PROCESSOR")/../.." && pwd)"
  SDK_ROOT="$(xcrun --sdk macosx --show-sdk-path)"
  XCODE_BUILD="$(xcodebuild -version | awk '/Build version/ {print $3}')"
  ARCH="$(basename "$(dirname "$CONST_VALUES")")"
  if "$PROCESSOR" \
      --toolchain-dir "$TOOLCHAIN_DIR" \
      --module-name FlowBreak \
      --sdk-root "$SDK_ROOT" \
      --xcode-version "$XCODE_BUILD" \
      --platform-family macOS \
      --deployment-target 13.0 \
      --target-triple "$ARCH-apple-macos13.0" \
      --source-file-list "$WORK/sources.list" \
      --swift-const-vals-list "$WORK/constvalues.list" \
      --output "$APP/Contents/Resources" \
      --no-app-shortcuts-localization \
      --force; then
    if [[ -d "$APP/Contents/Resources/Metadata.appintents" ]]; then
      echo "==> Embedded App Intents metadata (Shortcuts actions)"
    else
      echo "warning: the App Intents extractor ran but produced no metadata." >&2
    fi
  else
    echo "warning: App Intents metadata extraction failed; Shortcuts actions won't be available." >&2
  fi
  rm -rf "$WORK"
else
  echo "note: App Intents metadata not generated (needs a release build made with Xcode's build system, e.g. --universal)."
fi
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
