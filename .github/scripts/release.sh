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

notary=(--key "$HOME/.private_keys/AuthKey_${NOTARY_KEY_ID}.p8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")

build_dir="build"
archive="$build_dir/RFCReader.xcarchive"
export_dir="$build_dir/export"
app="$export_dir/RFCReader.app"
stage="$build_dir/dmg"

step() { printf '\n==> %s\n' "$1"; }

# notarytool's exit status does not say whether Apple accepted the submission, so
# the status is read from its result, and Apple's log is printed when it is not.
# Its exit status is ignored for the same reason: under set -e a non-zero one would
# end the script before the log is printed.
notarize() {
  local result id status
  result=$(xcrun notarytool submit "$1" "${notary[@]}" --wait --output-format json) || true
  # A submission refused before it has an ID (a wrong key or issuer) has neither.
  id=$(plutil -extract id raw - <<<"$result" 2>/dev/null) || id=""
  status=$(plutil -extract status raw - <<<"$result" 2>/dev/null) || status=""
  if [[ -z "$id" ]]; then
    echo "notarytool did not submit $1:" >&2
    echo "$result" >&2
    exit 1
  fi
  if [[ "$status" != "Accepted" ]]; then
    echo "Notarization of $1 ended as $status." >&2
    xcrun notarytool log "$id" "${notary[@]}" >&2 || true
    exit 1
  fi
}

step "Generating the Xcode project"
make xcodeproj

step "Archiving"
rm -rf "$archive" "$export_dir" "$stage"
# SELF_UPDATING starts the updater, which no other build does (Window/Updater.swift).
# Added to the conditions each target has, not in place of them.
# Signed with Developer ID from the start: automatic signing would resolve the
# archive to a development certificate, which export then discards but which must
# still exist, and the runner holds only the Developer ID one.
xcodebuild archive -project RFCReader.xcodeproj -scheme RFCReader \
  -destination 'generic/platform=macOS' -configuration Release \
  -archivePath "$archive" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS="\$(inherited) SELF_UPDATING" \
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
notarize "$zip"
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
# signature on the download itself. The runner's keychain holds the one identity.
codesign --force --sign "Developer ID Application" --timestamp "$dmg"

step "Notarizing the disk image"
notarize "$dmg"
xcrun stapler staple "$dmg"

echo "$dmg"
