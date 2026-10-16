# Datatracker data is published on GitHub Pages

*Decided October 2026. Amends "Datatracker data reaches the app as a published file", which put it on a release.*

The revisions workflow publishes `revisions.json`, `revisions-scan.json` and `groups.json` on the repository's GitHub Pages site, `https://rfc-reader.mazetti.me/`, and the app fetches them from there.
They were to live on the `revisions` prerelease, replaced daily with `gh release upload --clobber`, but the repository's releases are immutable: the first run created the release without assets, it became immutable when it was published, and every upload since has failed with HTTP 422, so the app has never received either file.

Immutable releases stay on, because they protect the releases that are versions.
A file replaced daily belongs somewhere that is replaced as a whole, and a Pages deployment is: each run uploads its output directory as the site, with no history to grow and no asset to clobber.
A branch served from raw.githubusercontent.com would have meant a workflow force-pushing a branch every day.

The next run reads its baselines, the scan record and the last `groups.json`, back from the site, where a 404 means a first run.
A failure to describe the groups republishes the previous `groups.json` and fails the run after the deployment, so the revisions still go out and the failure is still seen.
The site must be enabled in the repository's settings with GitHub Actions as its source.
The site has a custom domain of its own, `rfc-reader.mazetti.me`, set there too and by a DNS `CNAME` to `radiergummi.github.io`: without one, the github.io address redirects to the owner's user-site domain, and the first hop is plain HTTP, which App Transport Security refuses and the workflow's `curl` does not follow.
