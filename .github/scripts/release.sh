#!/bin/bash
#
# Builds a Developer ID signed, notarized and stapled disk image of the Mac app,
# for the release workflow (#911). Adapted from meetingFocus's Scripts/release.sh.
# The update feed is not made here: the maintainer signs it on their own machine.
#
# Needs the keychain .github/scripts/signing.sh sets up, and in the environment:
#   NOTARY_KEY_ID, NOTARY_ISSUER  the App Store Connect key notarytool submits with
#   BUILD_NUMBER                  CFBundleVersion, which Sparkle orders updates by
#
# Writes build/RFC-Reader-<version>.dmg and prints its path last.
#
set -euo pipefail
cd "$(dirname "$0")/../.."

: "${NOTARY_KEY_ID:?}"
: "${NOTARY_ISSUER:?}"
: "${BUILD_NUMBER:?}"

team_id="TH593VRB6W"
notary=(--key "$HOME/.private_keys/AuthKey_${NOTARY_KEY_ID}.p8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")

build_dir="build"
archive="$build_dir/RFCReader.xcarchive"
export_dir="$build_dir/export"
app="$export_dir/RFCReader.app"
stage="$build_dir/dmg"

step() { printf '\n==> %s\n' "$1"; }

step "Generating the Xcode project"
make xcodeproj

step "Archiving"
rm -rf "$archive" "$export_dir" "$stage"
# Signed with Developer ID from the start: automatic signing would resolve the
# archive to a development certificate, which export then discards but which must
# still exist, and the runner holds only the Developer ID one.
xcodebuild archive -project RFCReader.xcodeproj -scheme RFCReader \
  -destination 'generic/platform=macOS' -configuration Release \
  -archivePath "$archive" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$team_id" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  -quiet

step "Exporting with Developer ID"
xcodebuild -exportArchive -archivePath "$archive" \
  -exportOptionsPlist .github/scripts/ExportOptions.plist \
  -exportPath "$export_dir" -quiet

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
built_number=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$app/Contents/Info.plist")
if [[ "$built_number" != "$BUILD_NUMBER" ]]; then
  echo "The app's CFBundleVersion is $built_number, not $BUILD_NUMBER." >&2
  exit 1
fi
dmg="$build_dir/RFC-Reader-$version.dmg"

step "Verifying the signature"
codesign --verify --deep --strict --verbose=2 "$app"
# Captured first: grep -q exits at its first match, which would end codesign with
# SIGPIPE and fail the pipeline.
signature=$(codesign -d --verbose=4 "$app" 2>&1 || true)
grep -q 'flags=.*runtime' <<<"$signature" || {
  echo "The hardened runtime is not on; notarization would refuse the app." >&2
  exit 1
}
grep -q 'Authority=Developer ID Application' <<<"$signature" || {
  echo "The app is not signed with a Developer ID Application certificate." >&2
  exit 1
}
grep -q 'Timestamp=' <<<"$signature" || {
  echo "The signature has no secure timestamp; notarization would refuse the app." >&2
  exit 1
}

step "Notarizing the app"
zip="$build_dir/RFCReader-notarize.zip"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" "${notary[@]}" --wait
# Stapled, so the app stays trusted once copied out of the disk image.
xcrun stapler staple "$app"
rm -f "$zip"

step "Building the disk image"
mkdir -p "$stage"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
rm -f "$dmg"
hdiutil create -volname "RFC Reader $version" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null

# The disk image needs its own signature and ticket, or Gatekeeper finds no usable
# signature on the download itself.
identity=$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" | grep "$team_id" | head -1 \
  | sed -E 's/.*"(.*)".*/\1/')
[[ -n "$identity" ]] || {
  echo "No Developer ID Application identity for team $team_id." >&2
  exit 1
}
codesign --force --sign "$identity" --timestamp "$dmg"

step "Notarizing the disk image"
xcrun notarytool submit "$dmg" "${notary[@]}" --wait
xcrun stapler staple "$dmg"

echo "$dmg"
