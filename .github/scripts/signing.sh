#!/bin/bash
#
# Installs the release signing material into a throwaway keychain on the runner
# (#911). Adapted from meetingFocus, which adapted it from Secretive.
#
# The Developer ID key exists on the runner for the length of the build, in a
# keychain made for it on a VM thrown away after. That is the price of a release
# built by a public run from a public commit, which anyone can trace a download
# back to; signing on a laptop would keep the key home but leave nothing to check.
#
set -euo pipefail

: "${SIGNING_DATA:?missing the SIGNING_DATA secret (the Developer ID .p12, base64)}"
: "${SIGNING_PASSWORD:?missing the SIGNING_PASSWORD secret}"
: "${APPLE_API_KEY_DATA:?missing the APPLE_API_KEY_DATA secret (the App Store Connect .p8)}"
: "${APPLE_API_KEY_ID:?missing the APPLE_API_KEY_ID variable}"

keychain="release.keychain"
keychain_password="release"

# Removed however the script ends: it is the Developer ID private key.
trap 'rm -f Signing.p12' EXIT
echo "$SIGNING_DATA" | base64 -d -o Signing.p12

security create-keychain -p "$keychain_password" "$keychain"
security default-keychain -s "$keychain"
security list-keychains -s "$keychain"
# Locked, codesign would prompt, and a runner would wait for the timeout.
security unlock-keychain -p "$keychain_password" "$keychain"
# Unlocked for as long as the job may run (release.yml's timeout-minutes): the disk
# image is signed only after the app's notarization, which may wait for Apple long.
security set-keychain-settings -lut 7200 "$keychain"
security import ./Signing.p12 -k "$keychain" -P "$SIGNING_PASSWORD" -A -T /usr/bin/codesign
# Lets codesign use the key without a prompt that cannot appear.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null

# notarytool reads the App Store Connect key from disk, by its ID.
mkdir -p ~/.private_keys
printf '%s' "$APPLE_API_KEY_DATA" > ~/".private_keys/AuthKey_${APPLE_API_KEY_ID}.p8"

echo "Signing identities:"
security find-identity -v -p codesigning | grep "Developer ID Application" || {
  echo "No Developer ID Application identity was imported." >&2
  exit 1
}
