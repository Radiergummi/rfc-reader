#!/bin/bash
#
# Deploys the site in site/, and with it the update feed `make appcast` wrote, to
# rfc-reader.mazetti.me (#911). Adapted from meetingFocus's Scripts/publish-feed.sh.
#
# Refuses while any download the feed offers does not answer: an entry whose
# download fails is an update every installed copy fails to install. Before the
# first release there is no feed, and the site is deployed without one, so that
# the feed's address answers when `make appcast` asks it.
#
set -euo pipefail
cd "$(dirname "$0")/../.."

feed_url="https://rfc-reader.mazetti.me/appcast.xml"
appcast="site/public/appcast.xml"

step() { printf '\n==> %s\n' "$1"; }

# A deploy replaces every file the site serves, so a checkout without the newest feed
# would take updates away from every installed copy: refused when the live feed has
# a build the local one lacks, or there is a live feed and no local one.
highest_build() { sed -n 's/.*<sparkle:version>\([0-9]*\)<.*/\1/p' "$1" | sort -n | tail -1; }
step "Comparing with the live feed"
live="$(mktemp)"
status=$(curl -sS -o "$live" -w '%{http_code}' --max-time 20 "$feed_url")
case "$status" in
  200)
    if [[ ! -f "$appcast" ]]; then
      echo "$feed_url is live and $appcast is missing: deploying would remove the feed." >&2
      exit 1
    fi
    live_build=$(highest_build "$live")
    local_build=$(highest_build "$appcast")
    if [[ "${local_build:-0}" -lt "${live_build:-0}" ]]; then
      echo "The live feed offers build $live_build and $appcast only ${local_build:-none}: deploying would take it back." >&2
      exit 1
    fi
    ;;
  404) ;;
  *)
    echo "Fetching $feed_url answered $status." >&2
    exit 1
    ;;
esac

if [[ -f "$appcast" ]]; then
  step "Checking the feed"
  # Every entry signed, not only some: the older ones carry their signatures
  # whether or not the newest was signed.
  entries=$(grep -c '<item>' "$appcast" || true)
  signed=$(grep -c 'sparkle:edSignature=' "$appcast" || true)
  if [[ "$entries" -eq 0 || "$signed" -ne "$entries" ]]; then
    echo "The feed has $entries entries and $signed signatures; Sparkle refuses an unsigned one." >&2
    exit 1
  fi

  # Every entry's download, not only the newest: an older one whose download is
  # gone breaks updating for whoever still runs that version. One byte of each is
  # enough to know it answers.
  urls=$(grep -o 'url="[^"]*"' "$appcast" | sed 's/url="//;s/"$//')
  while read -r url; do
    printf '  %s ... ' "$url"
    code=$(curl -sSL -r 0-0 -o /dev/null -w '%{http_code}' --max-time 60 "$url") || code="failed"
    if [[ "$code" != "200" && "$code" != "206" ]]; then
      echo "$code"
      echo "Not publishing: that download does not answer." >&2
      exit 1
    fi
    echo "ok"
  done <<<"$urls"
else
  echo "No $appcast: deploying the site without a feed."
fi

step "Deploying the site"
(cd site && npx --yes wrangler@4.151.1 deploy)

if [[ ! -f "$appcast" ]]; then
  exit 0
fi

# The edge may serve the feed before for a little while; what counts is that the
# one just deployed is served, as XML.
step "Checking the published feed"
served="$(mktemp)"
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  type=$(curl -sS -o "$served" -w '%{content_type}' --max-time 20 "$feed_url") || type=""
  if cmp -s "$served" "$appcast"; then
    break
  fi
  echo "  not served yet (attempt $attempt)"
  sleep 6
done
if ! cmp -s "$served" "$appcast"; then
  echo "$feed_url does not serve the feed just deployed." >&2
  exit 1
fi
[[ "$type" == application/xml* || "$type" == text/xml* ]] || {
  echo "The feed is served as $type; Sparkle needs XML." >&2
  exit 1
}
echo "$feed_url serves the new feed ($type)."
