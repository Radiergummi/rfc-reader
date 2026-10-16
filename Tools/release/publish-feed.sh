#!/bin/bash
#
# Deploys the site in site/, and with it the update feed `make appcast` wrote, to
# rfc-reader.mazetti.me (#911). Adapted from meetingFocus's Scripts/publish-feed.sh.
#
# Refuses while any download the feed offers does not answer: an entry whose
# download fails is an update every installed copy fails to install.
#
set -euo pipefail
cd "$(dirname "$0")/../.."

feed_url="https://rfc-reader.mazetti.me/appcast.xml"
appcast="site/public/appcast.xml"

step() { printf '\n==> %s\n' "$1"; }

[[ -f "$appcast" ]] || {
  echo "No $appcast: run make appcast VERSION=<version> first." >&2
  exit 1
}

step "Checking the feed"
grep -q 'sparkle:edSignature' "$appcast" || {
  echo "The feed carries no EdDSA signature; Sparkle would refuse every update." >&2
  exit 1
}

# Every entry, not only the newest: an older one whose download is gone breaks
# updating for whoever still runs that version.
urls=$(grep -o 'url="[^"]*"' "$appcast" | sed 's/url="//;s/"$//')
[[ -n "$urls" ]] || {
  echo "The feed offers no downloads." >&2
  exit 1
}
while read -r url; do
  printf '  %s ... ' "$url"
  code=$(curl -sSL -o /dev/null -w '%{http_code}' --max-time 60 "$url" || echo 000)
  if [[ "$code" != "200" ]]; then
    echo "$code"
    echo "Not publishing: that download does not answer." >&2
    exit 1
  fi
  echo "ok"
done <<<"$urls"

step "Deploying the site"
(cd site && npx --yes wrangler@4 deploy)

step "Checking the published feed"
published=$(curl -sS --max-time 20 "$feed_url")
type=$(curl -sS -o /dev/null -w '%{content_type}' --max-time 20 "$feed_url")
grep -q 'sparkle:edSignature' <<<"$published" || {
  echo "The published feed carries no signature." >&2
  exit 1
}
[[ "$type" == application/xml* || "$type" == text/xml* ]] || {
  echo "The feed is served as $type; Sparkle needs XML." >&2
  exit 1
}
echo "$feed_url is live and signed ($type)."
