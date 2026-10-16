# Datatracker data is published to Cloudflare R2

*Decided October 2026. Amends "Datatracker data reaches the app as a published file", which put it on a release.*

The revisions workflow publishes `revisions.json`, `revisions-scan.json` and `groups.json` to the `rfc-reader` Cloudflare R2 bucket, and the app fetches them from its public domain, `https://data.rfc-reader.mazetti.me/`.
They were to live on the `revisions` prerelease, replaced daily with `gh release upload --clobber`, but the repository's releases are immutable: the first run created the release without assets, it became immutable when it was published, and every upload since has failed with HTTP 422, so the app has never received either file.

Immutable releases stay on, because they protect the releases that are versions.
GitHub Pages was tried first and dropped. A Pages deployment replaces the whole site, so anything else published on it (the project's website, Sparkle's appcast, #911) would have to be deployed by the same run. And the github.io address redirected through the owner's user-site domain over plain HTTP, which App Transport Security refuses.
A bucket is written one object at a time: each run replaces its own files and nothing else, so the website on `rfc-reader.mazetti.me` is deployed on its own.
A branch served from raw.githubusercontent.com would have meant a workflow force-pushing a branch every day.

The workflow writes through R2's S3 API, signed by `curl --aws-sigv4`, with an R2 API token scoped to the bucket: the repository variables `CLOUDFLARE_ACCOUNT_ID` and `R2_ACCESS_KEY_ID` and the secret `R2_SECRET_ACCESS_KEY`.
`revisions.json` is written before the scan record that describes it, so a run that fails between the two makes the next one rescan rather than trust a record of what was not published.
The next run reads its baselines, the scan record and the last `groups.json`, back from the public domain, where a 404 means a first run.
A failure to describe the groups leaves the previous `groups.json` in the bucket and fails the run after the rest is published, so the revisions still go out and the failure is still seen.
