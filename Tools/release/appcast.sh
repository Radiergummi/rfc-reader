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
# The site must be deployed once before the first release (`make publish-feed`
# deploys it without a feed), so that the feed's address answers.
#
# Usage: make appcast VERSION=<version>, which passes the build directory of
# this checkout's DerivedData, where the Sparkle the app is built with is.
#
set -euo pipefail
cd "$(dirname "$0")/../.."

version="${1:?usage: make appcast VERSION=<version>}"
build_dir="${2:?could not read BUILD_DIR from xcodebuild -showBuildSettings}"
repository="Radiergummi/rfc-reader"
tag="v$version"
disk_image="RFC-Reader-$version.dmg"
updates=".build/updates"
mount_point="$updates/mount"

step() { printf '\n==> %s\n' "$1"; }

step "Finding Sparkle's generate_appcast"
xcodebuild -resolvePackageDependencies -project RFCReader.xcodeproj -scheme RFCReader >/dev/null
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

hdiutil detach "$mount_point" >/dev/null 2>&1 || true
rm -rf "$updates"
# hdiutil refuses a mount point outside /Volumes that does not exist yet.
mkdir -p "$mount_point"
gh release download "$tag" --repo "$repository" --pattern "$disk_image" --dir "$updates"

# Made by release.yml, run for this tag, not only by some workflow of the repository.
step "Verifying that the release workflow built it"
gh attestation verify "$updates/$disk_image" --repo "$repository" \
  --signer-workflow "$repository/.github/workflows/release.yml" \
  --source-ref "refs/tags/$tag"

# The feed is the one the released app reads, so it is the one its entry joins.
step "Reading the build number and the feed's address"
hdiutil attach "$updates/$disk_image" -nobrowse -readonly -mountpoint "$mount_point" >/dev/null
trap 'hdiutil detach "$mount_point" >/dev/null 2>&1 || true' EXIT
build_number=$(plutil -extract CFBundleVersion raw "$mount_point/RFCReader.app/Contents/Info.plist")
feed_url=$(plutil -extract SUFeedURL raw "$mount_point/RFCReader.app/Contents/Info.plist")
hdiutil detach "$mount_point" >/dev/null
trap - EXIT
echo "$tag is build $build_number, with its feed at $feed_url"

# Seeded from the published feed, so the releases before keep their entries:
# generate_appcast keeps what the feed in its directory holds. A 404 is the first
# release only while no feed is committed either; anything else stops here rather
# than publish a feed that forgot them.
step "Reading the published feed"
status=$(curl -sS -o "$updates/appcast.xml" -w '%{http_code}' --max-time 20 "$feed_url")
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
    if [[ -f site/public/appcast.xml ]]; then
      echo "$feed_url answers 404 but site/public/appcast.xml exists: run make publish-feed to restore it first." >&2
      exit 1
    fi
    rm -f "$updates/appcast.xml"
    echo "No feed is published yet: this is the first release."
    ;;
  *)
    echo "Fetching $feed_url answered $status." >&2
    exit 1
    ;;
esac

# Pinned to the release's own tag, not releases/latest, which would point every
# entry at the newest download. Every version is kept: an entry dropped is a
# version whose users are no longer told about anything newer than theirs.
step "Generating and signing the feed"
"$generate_appcast" --account rfc-reader --maximum-versions 0 \
  --download-url-prefix "https://github.com/$repository/releases/download/$tag/" \
  "$updates"

# The new entry's own signature: the older entries copied from the published feed
# carry theirs whether or not this one was signed.
awk -v RS='</item>' -v entry="<sparkle:version>$build_number</sparkle:version>" \
  'index($0, entry) && /sparkle:edSignature=/ {found = 1} END {exit !found}' \
  "$updates/appcast.xml" || {
  echo "The feed has no signed entry for build $build_number; is the rfc-reader key in this keychain?" >&2
  exit 1
}

cp "$updates/appcast.xml" site/public/appcast.xml
echo
echo "Wrote site/public/appcast.xml. Next: make publish-feed, then commit the feed."
