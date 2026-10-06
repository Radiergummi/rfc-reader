# Datatracker data reaches the app as a published file

*Decided September 2026.*
Which drafts are revising an RFC cannot be asked of datatracker one document at a time: it records the relation only once a draft is published, so the answer means reading the header of every adopted draft.
One scheduled GitHub Action (`revisions.yml`) does that for every user and publishes one small JSON file, `revisions.json`, on the `revisions` release.
The app fetches it at launch and on activation, caches it beside the index, and works offline from the cached copy, saying "as of" once it is more than three days old.
A snapshot shipped in a pack would be as stale as the pack, and drafts change weekly.
Later datatracker features that need refreshed data reuse this path.
The design is `docs/superpowers/specs/2026-09-29-rfc-revisions-design.md`.
