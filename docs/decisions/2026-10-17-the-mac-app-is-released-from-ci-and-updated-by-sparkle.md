# The Mac app is released from CI and updated by Sparkle

*Decided October 2026 (#911).*

The Mac app is distributed outside the App Store as a Developer ID build, and updates itself with Sparkle. The App Store build that VISION.md plans would leave Sparkle out; that is for when it exists.

A release is made by `.github/workflows/release.yml` on a `v*` tag, not on a laptop. It tests, archives with Developer ID, notarizes and staples the app, packages it in a disk image that is signed, notarized and stapled too, attests the image's build provenance, and makes a draft release with it. The tag must match `CFBundleShortVersionString` in `project.yml`. `CFBundleVersion` is the run number, because Sparkle orders updates by it and two releases may never share one; a local build is `1`.
A build made on a laptop can be traced back to nothing; one made by a public run from a public commit can, with `gh attestation verify`. The price is that the Developer ID key is on the runner for the length of the build, in a keychain made for it.

Two signatures are kept apart. GitHub attests the build. The maintainer signs the update feed with the EdDSA key whose public half is `SUPublicEDKey`, on their own machine, after publishing the draft release. So the workflow alone cannot ship an update. The maintainer's machine could, since it holds the Developer ID certificate too; what the attestation adds is that a release can be checked against the source. The key is the app's own, not shared with another app, so a leak is confined to this one; if it is lost, no installed copy can be updated again.

The signing material is the team's: the Developer ID certificate is the one every app of the team signs with, while the App Store Connect key that notarizes is this repository's own, so it can be revoked alone.

The feed is served from the project's site on `rfc-reader.mazetti.me`, beside the website, and the datatracker files from the R2 bucket on `data.rfc-reader.mazetti.me` ("Datatracker data is published to Cloudflare R2").
The app is sandboxed, so Sparkle installs through its launcher service, reached through two `mach-lookup` exceptions. Only a build of `.github/scripts/release.sh` updates itself: it compiles with the condition `SELF_UPDATING`, and the updater starts only when that is set. Sparkle installs over the running bundle, so a local build that started it, a Release one from `make install` or `make trace` as much as a Debug one, could be offered the published release and replace itself with it, and a trace could be interrupted by a scheduled check. Every build shares the bundle ID and so the defaults Sparkle reads first, so no runtime setting could tell them apart; the configuration could not either, since Release is built locally too.
