#!/bin/bash
#
# Makes the signed update feed for a published release (#911), into
# site/public/appcast.xml, for `make publish-feed` to deploy.
#
# Run on the maintainer's machine, after the release workflow made the draft
# release and the maintainer published it: the feed is signed with the EdDSA key
# in this machine's keychain (account rfc-reader), which never reaches CI. The disk
# image signed is the one the workflow attested, checked before it is signed.
#
# Usage: Tools/release/appcast.sh <version>, or make appcast VERSION=<version>
#
set -euo pipefail
cd "$(dirname "$0")/../.."

version="${1:?usage: Tools/release/appcast.sh <version>}"
repository="Radiergummi/rfc-reader"
feed_url="https://rfc-reader.mazetti.me/appcast.xml"
tag="v$version"
disk_image="RFC-Reader-$version.dmg"
updates=".build/updates"

step() { printf '\n==> %s\n' "$1"; }

step "Finding Sparkle's generate_appcast"
make xcodeproj >/dev/null
xcodebuild -resolvePackageDependencies -project RFCReader.xcodeproj -scheme RFCReader >/dev/null
# This checkout's own DerivedData, which holds the Sparkle the app is built with.
build_dir=$(xcodebuild -project RFCReader.xcodeproj -scheme RFCReader -destination 'generic/platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILD_DIR /{print $2; exit}')
generate_appcast="${build_dir%/Build/Products}/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
[[ -x "$generate_appcast" ]] || {
  echo "No generate_appcast at $generate_appcast." >&2
  exit 1
}

# A draft's assets are not public, so a feed pointing at one would offer a
# download that fails.
step "Checking that $tag is published"
is_draft=$(gh release view "$tag" --repo "$repository" --json isDraft --jq .isDraft)
[[ "$is_draft" == "false" ]] || {
  echo "$tag is still a draft: publish it first." >&2
  exit 1
}

rm -rf "$updates"
mkdir -p "$updates"
gh release download "$tag" --repo "$repository" --pattern "$disk_image" --dir "$updates"

step "Verifying that the release workflow built it"
gh attestation verify "$updates/$disk_image" --repo "$repository"

step "Reading the build number"
mount_point="$updates/mount"
hdiutil attach "$updates/$disk_image" -nobrowse -readonly -mountpoint "$mount_point" >/dev/null
build_number=$(plutil -extract CFBundleVersion raw "$mount_point/RFCReader.app/Contents/Info.plist")
hdiutil detach "$mount_point" >/dev/null
echo "$tag is build $build_number"

# Seeded from the published feed, so the releases before keep their entries:
# generate_appcast keeps what the feed in its directory holds. A 404 is the first
# release; any other failure stops here rather than publish a feed that forgot them.
step "Reading the published feed"
status=$(curl -sS -o "$updates/appcast.xml" -w '%{http_code}' "$feed_url")
case "$status" in
  200)
    published=$(sed -n 's/.*<sparkle:version>\([0-9]*\)<.*/\1/p' "$updates/appcast.xml" | sort -n | tail -1)
    # Sparkle offers only a higher CFBundleVersion, and generate_appcast would
    # replace an entry of the same build rather than add one.
    if [[ -n "$published" && "$build_number" -le "$published" ]]; then
      echo "Build $build_number is not above the published build $published." >&2
      exit 1
    fi
    echo "Build $build_number follows the published build ${published:-none}."
    ;;
  404)
    rm -f "$updates/appcast.xml"
    echo "No feed is published yet: this is the first release."
    ;;
  *)
    echo "Fetching $feed_url answered $status." >&2
    exit 1
    ;;
esac

# Pinned to the release's own tag, not releases/latest, which would point every
# entry at the newest download.
step "Generating and signing the feed"
"$generate_appcast" --account rfc-reader \
  --download-url-prefix "https://github.com/$repository/releases/download/$tag/" \
  "$updates"

grep -q 'sparkle:edSignature' "$updates/appcast.xml" || {
  echo "The feed carries no EdDSA signature; Sparkle would refuse every update." >&2
  exit 1
}
grep -q "<sparkle:version>$build_number</sparkle:version>" "$updates/appcast.xml" || {
  echo "The feed has no entry for build $build_number." >&2
  exit 1
}

cp "$updates/appcast.xml" site/public/appcast.xml
echo
echo "Wrote site/public/appcast.xml. Next: make publish-feed, then commit the feed."
