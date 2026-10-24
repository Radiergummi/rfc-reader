# The App Store builds are a target without Sparkle, uploaded from CI

*Decided 24 October 2026 (#994, part of #740; the maintainer's answers are recorded on the issue). A plan: nothing of it is built yet.*

The Mac app's releases are Developer ID builds that update themselves with Sparkle ("The Mac app is released from CI and updated by Sparkle"). VISION.md plans an App Store build on both platforms, and a TestFlight build of the iOS app for testers. This record plans what those need on top of what exists, so that the work can be split into issues and the maintainer's part is listed in one place. No release of the app has been tagged yet. When the first is stays open, and nothing holds releases back until then.

## The Mac App Store build is a second macOS target

A Mac App Store build may not update itself (App Review Guideline 2.4.5 (vii)), and its entitlements may not carry the two `mach-lookup` temporary exceptions that Sparkle's installer is reached through. Review asks for a justification of any temporary exception, and "to update outside the store" isn't one. So the App Store build must link no Sparkle, embed none of its helpers or XPC services, and declare neither the exceptions nor the `SU…` keys. Starting the updater only under `SELF_UPDATING` is not enough: the framework is linked and embedded in every macOS build.

- **The approach: a second app target, `RFCReaderAppStore`, macOS only, made from the same XcodeGen target template as `RFCReader`.** It has the same sources, the same product name, `RFCReader`, and the same Safari extension, and differs in three ways:
  - no Sparkle package dependency;
  - entitlements without the `mach-lookup` exceptions;
  - Info properties without `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks` and `SUEnableInstallerLauncherService`.

  It compiles with a condition, `APP_STORE`, which leaves out `Window/Updater.swift` and its three call sites: `AppDelegate`, `AboutCommands` (Check for Updates…) and `SettingsView` (the Updates setting). It gets a scheme of its own, since the two targets build the same product.
- **Why a target, not a build configuration.** Xcode cannot link a package product in one configuration and not another. A configuration that strips `Sparkle.framework` after linking would leave a load command that stops the app at launch. XcodeGen also writes one entitlements file per target, so a second set of entitlements would have to be a hand-maintained file beside the generated ones.
- **Why a condition, not `canImport(Sparkle)`.** Every target in the project shares the build products directory, so `canImport(Sparkle)` may come out true in a target that doesn't depend on Sparkle. A condition the target sets is what the code can rely on.
- **The bundle ID stays `me.mazetti.rfc-reader`.** With it, the Mac App Store app joins the iOS app's record (universal purchase), its data and later its CloudKit container (#655). The two Mac builds can then not be installed side by side without sharing a sandbox container, which is what a person moving from one to the other wants anyway.
- **Distribution needs its own certificates and profiles.** The Developer ID build ships as a disk image. The App Store build is a signed installer package, which needs an Apple Distribution certificate, a Mac Installer Distribution certificate and an App Store provisioning profile for the app and for its extension.
- **Both channels stay.** The Developer ID build and its Sparkle updates continue beside the Mac App Store build. The question is decided again once the Mac App Store build has shipped one release: whether the Developer ID channel then ends with a last Sparkle update that points to the store.

## The App Store builds go to TestFlight from CI

The Mac release is made by `release.yml` on a `v*` tag, so that a build can be traced to a public commit. The App Store builds follow it.

- **Two jobs beside the Developer ID one, on the same tag:** an iOS archive, and the Mac App Store target's archive. Each is exported with the method `app-store-connect` and the export option `destination: upload`, so `xcodebuild -exportArchive` uploads to App Store Connect itself, authenticated with an App Store Connect API key (`-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID`). No separate upload tool and no new third-party action is needed.
- **The uploaded build goes to TestFlight.** Submitting it for review stays a person's step in App Store Connect.
- **The iOS build is the existing `RFCReader` target, unchanged.** It signs with the target's one entitlements file, the macOS sandbox keys and the `mach-lookup` exceptions included, as device builds do now. The first upload's validation is where that is confirmed for distribution.
- **The build number is the run number, as now.** App Store Connect requires it to grow within a version on each platform, which the run number does. All three builds of a release share it.
- **Signing happens on the runner, as for Developer ID:** a keychain made for the job, with the certificates imported from secrets and removed after.
  - **The certificates are one PKCS#12 secret.** The Apple Distribution and Mac Installer Distribution certificates go in one PKCS#12 secret with its password, beside `SIGNING_DATA`, as the Developer ID certificate does. The four App Store provisioning profiles (app and extension, iOS and macOS) are made by `-allowProvisioningUpdates` with the API key, so that no profile has to be renewed in a secret by hand.
  - **Cloud-managed certificates were considered and rejected.** Xcode's cloud-managed distribution certificate needs no certificate on the runner at all, but it needs an API key with the Admin role, or one granted access to cloud-managed distribution certificates. That would put an Admin key in a GitHub secret.
- **A second App Store Connect API key uploads and makes profiles.** The repository already has one for notarization (`APPLE_API_KEY_DATA`), which the Sparkle decision made this repository's own so it can be revoked alone. It keeps its role. Uploading builds needs at least the Developer role, and making profiles with `-allowProvisioningUpdates` may need App Manager; the new key gets what those need and no more, and like the first it can be revoked alone.
- **TestFlight gets tagged releases only.** VISION.md's roadmap wants "TestFlight for yourself" early, and a tagged release is enough for that. Builds from every push to `main` for internal testers can come later, from a workflow with its own run-number range so that they never collide with a release.
- **The Xcode that archives must be a released one.** The release workflow archives with Xcode 26.6 today. Each spring App Store Connect starts refusing uploads built with the previous year's SDK, and the archive then has to move to Xcode 27; `app-build-xcode-27` already builds with it. `AppIcon-27` is compiled only by Xcode 27 (`project.yml`, `APP_ICON_2700`).
- **Once uploads exist, CI builds iOS in Release too.** CI's Release build (#992) is macOS only, the platform released today.

## Export compliance

The app uses encryption only through the system: HTTPS through `URLSession`, and CryptoKit's SHA-256 for integrity checks and identifiers (`DataPack`, `SpotlightEntry`, `Annotations/Target`). Using the operating system's encryption, and hashing for integrity or authentication, are the exempt cases in Apple's export-compliance questions.

- **`ITSAppUsesNonExemptEncryption: false`** in `project.yml`'s Info properties, so that no upload stops at the question. With it there is no documentation to upload and no French declaration to file.
- The maintainer confirms that answer in App Store Connect once, for the app record. It is a legal statement, and this record is not legal advice.

## CloudKit

No CloudKit is built: the app declares no iCloud entitlement, so its SwiftData store stays local, there is no schema to deploy, and **CloudKit does not gate a submission**. The store is opened with SwiftData's default configuration (`UserData.container()`), which syncs as soon as the app has an iCloud container entitlement. So neither target may gain one before #655 is ready.

It gates the first TestFlight or App Store build that contains sync (#655). Builds distributed through TestFlight and the App Store use CloudKit's production environment, which has only the schema that has been deployed to it in the CloudKit Console. A build that syncs before the schema is deployed fails to save. Once deployed, a production schema can only grow: record types and fields can't be removed or renamed. So every later change to the synced SwiftData models must be additive, and that constraint belongs in ARCHITECTURE.md when sync lands. #655 already scopes "a written release step for initializing the development schema and deploying it to production". That step goes into the release checklist before the first such tag.

## App Store metadata, and what waits on the IETF Trust

- **What the listing needs:**
  - a name, a subtitle, a description, keywords and a category (Reference, which `LSApplicationCategoryType` already says);
  - screenshots for the iPhone, the iPad and the Mac;
  - a support URL and a privacy policy URL;
  - the age rating questionnaire;
  - App Privacy answers;
  - the price and the countries the app is offered in.
- **App Privacy is "Data Not Collected"**, as the privacy manifest declares (#991). The app sends no identifiers and collects nothing, and the documents it fetches are public. The privacy policy can say so in a paragraph and live on `rfc-reader.mazetti.me` beside the feed. It doesn't exist yet.
- **The Contacts card needs no entitlement (#993).** `NSContactsUsageDescription` may be unnecessary too: the app never asks for Contacts access, and in the check that settled #993 its own authorization stayed `.notDetermined`. That check didn't press Add to Contacts, though, so it is worth confirming before review asks about the key.
- **The license.** The code is AGPL-3.0, and the maintainer is its only copyright holder apart from dependency updates, so they can publish it under the App Store's terms as well, which settles the usual tension between the GPL licenses and those terms. That holds only while every contribution is theirs. A contributor license agreement, asked for in a contributing guide (the repository has none yet), keeps it so.
- **Third-party content.** App Store Connect asks whether the app shows third-party content and whether the developer has the rights to it. The app shows RFCs in four ways:
  - RFCs fetched from the RFC Editor on the device and shown as published. The app redistributes none of them; DATA_PIPELINE.md has what the licenses say.
  - The RFC index in the bundle (#770), the RFC Editor's `rfc-index.xml` as published, which holds each RFC's title, authors and abstract. The abstracts are RFC text, redistributed unchanged: what the IETF Trust Legal Provisions grant for RFCs from November 2008 on, and what DATA_PIPELINE.md leaves open for older ones.
  - The indexes pack in the bundle, which holds identifiers and anchors and no RFC text.
  - The converted legacy RFCs, the `legacy-xml` pack.

  Only the pack is a modified text, the case #215 asked the IETF Trust about. Nothing in a release build downloads it today, so **#215 doesn't gate a first submission** as long as "Read everything offline" isn't in it.
- **The Trust is asked in the same correspondence as #215**, about the app's listing in the App Store and about the bundled index's abstracts of RFCs from before November 2008. That answers the content-rights question with a letter rather than a reading of the licenses.
- **The name is "RFC Reader" if it is free.** VISION.md expects it to be taken. An App Store name is unique across the store and is reserved by making the app record, so making the record is how it is tried. If it is taken, a name is chosen from a short list before any metadata is written.
- **The app is one free, universal purchase.** Free, with no purchase inside it, and one record for the Mac and iOS apps, which the shared bundle ID allows. A free app needs no Paid Applications agreement, and no tax or banking forms.

## Checklist before a first submission

The builds are distributed in this order: TestFlight on iOS, then the App Store on iOS, then the Mac App Store. The list is in order too, and items marked **(maintainer)** are the maintainer's alone.

- [ ] **(maintainer)** Make the app record in App Store Connect for `me.mazetti.rfc-reader` (iOS and macOS), as one free, universal purchase, to reserve "RFC Reader". If the name is taken, choose one from a short list before any metadata is written.
- [ ] **(maintainer)** Choose the countries the app is offered in.
- [ ] **(maintainer)** Write to the IETF Trust about the App Store listing and the bundled index's abstracts of RFCs from before November 2008, in the same correspondence as #215.
- [ ] Add `ITSAppUsesNonExemptEncryption: false` to `project.yml`, and settle whether `NSContactsUsageDescription` stays.
- [ ] Build the `RFCReaderAppStore` target, its `APP_STORE` condition and its entitlements, with a CI build of it, unsigned, beside the Developer ID one.
- [ ] **(maintainer)** Make the second App Store Connect API key, for uploads and profiles, and store it as a secret.
- [ ] **(maintainer)** Make the Apple Distribution and Mac Installer Distribution certificates, and store them as one PKCS#12 secret with its password.
- [ ] Add the iOS and the Mac App Store archive-and-upload jobs to `release.yml`, and an iOS Release build to CI.
- [ ] Write the privacy policy page on `rfc-reader.mazetti.me`, and a support page or address.
- [ ] **(maintainer)** Tag the first release that uploads, when it suits; the date is open. Install the TestFlight build on a device and test it.
- [ ] Take the screenshots: iPhone, iPad and Mac, in English and German, since the app's chrome is localized.
- [ ] **(maintainer)** Write the description, keywords and subtitle in English and German. Answer the age rating, App Privacy ("Data Not Collected"), export compliance and content-rights questions, and give review notes (no account is needed to use the app).
- [ ] **(maintainer)** Submit the iOS app for review, and once it is in the store, the Mac App Store build.

After the first submission:

- [ ] Before a release that contains sync (#655), deploy the CloudKit schema to production, and from then on keep schema changes additive.
- [ ] Before "Read everything offline" ships, wait for the IETF Trust's answer (#215).
- [ ] Before the spring SDK deadline, archive with Xcode 27.
- [ ] **(maintainer)** Once the Mac App Store build has shipped one release, decide whether the Developer ID channel continues.
