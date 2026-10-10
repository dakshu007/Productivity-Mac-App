#!/usr/bin/env bash
# Release build: Developer ID signing + hardened runtime + notarization + stapling.
#
# Required environment:
#   DEVELOPER_ID_APPLICATION  e.g. "Developer ID Application: Jane Doe (TEAMID1234)"
#   and EITHER
#     NOTARY_PROFILE          a keychain profile created with
#                             `xcrun notarytool store-credentials`
#   OR
#     APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD (app-specific password)
#
# Refuses to continue if anything is missing — it never produces an unsigned
# "release" artifact.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() { echo "error: $*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS required."
for tool in xcrun codesign hdiutil security; do
  command -v "$tool" >/dev/null || fail "'$tool' not found (install Xcode)."
done
[[ -n "${DEVELOPER_ID_APPLICATION:-}" ]] || fail "DEVELOPER_ID_APPLICATION is not set."
security find-identity -v -p codesigning | grep -Fq "$DEVELOPER_ID_APPLICATION" \
  || fail "signing identity '$DEVELOPER_ID_APPLICATION' is not in the keychain."

NOTARY_ARGS=()
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  NOTARY_ARGS=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
else
  fail "set NOTARY_PROFILE, or APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD."
fi

"$ROOT/Scripts/build_universal.sh"
APP="$ROOT/build/FlowBreak.app"

echo "==> Signing with hardened runtime: $DEVELOPER_ID_APPLICATION"
codesign --force --options runtime --timestamp \
  --entitlements "$ROOT/Resources/FlowBreak.entitlements" \
  --sign "$DEVELOPER_ID_APPLICATION" "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"

DMG_SUFFIX="" "$ROOT/Scripts/build_dmg.sh"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/build/dmg/FlowBreak-$VERSION.dmg"
codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$DMG"

echo "==> Submitting to Apple notary service (this can take a few minutes)"
xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

( cd "$(dirname "$DMG")" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256" )
echo "==> Signed, notarized and stapled: $DMG"
