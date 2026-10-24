# The App Store builds are a target without Sparkle, uploaded from CI

*Proposed October 2026 (#994, part of #740); a plan, nothing of it built. The questions marked **Open** are the maintainer's.*

The Mac app is released outside the App Store as a Developer ID build that updates itself with Sparkle ("The Mac app is released from CI and updated by Sparkle"). VISION.md plans an App Store build on both platforms, and a TestFlight build of the iOS app for testers. This record plans what those need on top of what exists, so that the work can be split into issues and the maintainer's part is listed in one place. Nothing here is released before the maintainer lifts the current hold on releases.

## The Mac App Store build is a second macOS target

A Mac App Store build may not update itself (App Review Guideline 2.4.5), and its entitlements may not carry the two `mach-lookup` temporary exceptions that Sparkle's installer is reached through. Review asks for a justification of any temporary exception, and "to update outside the store" isn't one. So the App Store build must link no Sparkle, embed none of its helpers or XPC services, and declare neither the exceptions nor the `SU…` keys. Starting the updater only under `SELF_UPDATING` is not enough: the framework is linked and embedded in every macOS build.

- **The approach: a second app target, `RFCReaderAppStore`, macOS only, made from the same XcodeGen target template as `RFCReader`.** It has the same sources and the same Safari extension, and differs in three ways:
  - no Sparkle package dependency;
  - entitlements without the `mach-lookup` exceptions;
  - Info properties without `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks` and `SUEnableInstallerLauncherService`.

  It compiles with a condition, `APP_STORE`, which leaves out `Window/Updater.swift` and its three call sites: `AppDelegate`, `AboutCommands` and `SettingsView` (the Updates setting).
- **Why a target, not a build configuration.** Xcode cannot link a package product in one configuration and not another. A configuration that strips `Sparkle.framework` after linking would leave a load command that stops the app at launch. XcodeGen also writes one entitlements file per target, so a second set of entitlements would have to be a hand-maintained file beside the generated ones.
- **Why a condition, not `canImport(Sparkle)`.** Every target in the project shares the build products directory, so `canImport(Sparkle)` may come out true in a target that doesn't depend on Sparkle. A condition the target sets is what the code can rely on.
- **The bundle ID stays `me.mazetti.rfc-reader`.** With it, the Mac App Store app joins the iOS app's record (universal purchase), its data and later its CloudKit container (#655). The two Mac builds can then not be installed side by side without sharing a sandbox container, which is what a person moving from one to the other wants anyway.
- **Distribution needs its own certificates and profiles.** The Developer ID build ships as a disk image. The App Store build is a signed installer package, which needs an Apple Distribution certificate, a Mac Installer Distribution certificate and an App Store provisioning profile for the app and for its extension.
- **Open:** whether the Developer ID channel continues once the App Store build exists, or ends with a last Sparkle update that points to the store.

## iOS goes to TestFlight from CI

The Mac release is made by `release.yml` on a `v*` tag, so that a build can be traced to a public commit. The App Store builds follow it.

- **Two jobs beside the Developer ID one, on the same tag:** an iOS archive, and the Mac App Store target's archive. Each is exported with the method `app-store-connect` and the export option `destination: upload`, so `xcodebuild -exportArchive` uploads to App Store Connect itself, authenticated with an App Store Connect API key (`-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID`). No separate upload tool and no new third-party action is needed.
- **The uploaded build goes to TestFlight.** Submitting it for review stays a person's step in App Store Connect.
- **The build number is the run number, as now.** App Store Connect requires it to grow within a version on each platform, which the run number does. All three builds of a release share it.
- **Signing happens on the runner, as for Developer ID:** a keychain made for the job, with the certificates imported from secrets and removed after.
  - **Proposed:** the Apple Distribution and Mac Installer Distribution certificates as one PKCS#12 secret with its password, beside `SIGNING_DATA`. The four App Store provisioning profiles (app and extension, iOS and macOS) are made by `-allowProvisioningUpdates` with the API key, so that no profile has to be renewed in a secret by hand.
  - **The alternative:** Xcode's cloud-managed distribution certificate, which needs no certificate on the runner at all. It needs an API key with the Admin role, or one granted access to cloud-managed distribution certificates.
- **Open:** which App Store Connect API key uploads. The repository already has one for notarization (`APPLE_API_KEY_DATA`), which the Sparkle decision made this repository's own so it can be revoked alone. Uploading builds needs at least the Developer role, and making profiles may need App Manager or Admin. Either that key's role is raised, or a second key is made for uploads. The certificate route depends on the answer.
- **Open:** whether TestFlight gets only tagged releases, or also every push to `main` for internal testers. VISION.md's roadmap wants "TestFlight for yourself" early. The plan works for both; a build from `main` would need its own run-number range so that it never collides with a release.
- **The Xcode that archives must be a released one.** The release workflow archives with Xcode 26.6 today. Each spring App Store Connect starts refusing uploads built with the previous year's SDK, and the archive then has to move to Xcode 27; `app-build-xcode-27` already builds with it. `AppIcon-27` is compiled only by Xcode 27 (`project.yml`, `APP_ICON_2700`).
- **Once uploads exist, CI builds iOS in Release too.** #992 builds only macOS in Release.

## Export compliance

The app uses encryption only through the system: HTTPS through `URLSession`, and CryptoKit's SHA-256 for integrity checks and identifiers (`DataPack`, `SpotlightEntry`, `Annotations/Target`). Using the operating system's encryption, and hashing for integrity or authentication, are the exempt cases in Apple's export-compliance questions.

- **Proposed:** `ITSAppUsesNonExemptEncryption: false` in `project.yml`'s Info properties, so that no upload stops at the question. With it there is no documentation to upload and no French declaration to file.
- The maintainer confirms that answer in App Store Connect once, for the app record. It is a legal statement, and this record is not legal advice.

## CloudKit

No CloudKit is built: the app declares no iCloud entitlement and opens its SwiftData store locally, so there is no schema to deploy, and **CloudKit does not gate a submission**.

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
- **The Contacts card needs no entitlement (#993).** `NSContactsUsageDescription` may be unnecessary too, since the app never asks for Contacts access. That is worth confirming before review asks about it.
- **The license.** The code is AGPL-3.0, and the maintainer is its only copyright holder apart from dependency updates, so they can publish it under the App Store's terms as well. That is the usual tension between GPL licenses and the App Store's terms, and it stays theirs alone only while every contribution is theirs. A contributor license, or a note in the contributing guide, keeps it so.
- **Third-party content.** App Store Connect asks whether the app shows third-party content and whether the developer has the rights to it. The app shows RFCs in three ways:
  - RFCs fetched from the RFC Editor and shown as published. These are covered for RFCs under the IETF Trust Legal Provisions; DATA_PIPELINE.md has what is known about older ones.
  - The indexes pack in the bundle, which holds identifiers and anchors and no RFC text.
  - The converted legacy RFCs, the `legacy-xml` pack.

  Only the pack waits on the IETF Trust's answer (#215). Nothing in a release build downloads it today, so **#215 doesn't gate a first submission** as long as "Read everything offline" isn't in it.
- **Open:** whether to ask the Trust, in the same correspondence, about the app's listing as a paid product. That answers the content-rights question with a letter rather than a reading of the licenses.
- **Open:** the app's name. VISION.md expects "RFC Reader" to be taken. An App Store name is unique across the store and is reserved by making the app record.
- **Open:** the price and the business model: paid up front, free, or free with a purchase. Also which countries, and whether the Mac and iOS apps are one purchase (universal purchase, which the shared bundle ID allows).

## Checklist before a first submission

In order. Items marked **(maintainer)** are the maintainer's alone.

1. **(maintainer)** Decide the name, and reserve it by making the app record in App Store Connect for `me.mazetti.rfc-reader` (iOS and macOS).
2. **(maintainer)** Decide the price, the business model and the countries, and sign the Paid Applications agreement in App Store Connect if the app is paid, with its tax and banking forms.
3. **(maintainer)** Decide the distribution order: TestFlight on iOS first, then the App Store on iOS, then the Mac App Store. Decide also whether the Developer ID channel continues.
4. Land the privacy manifest (#991), the Release build in CI (#992) and the Contacts finding (#993).
5. Add `ITSAppUsesNonExemptEncryption: false` to `project.yml`.
6. Build the `RFCReaderAppStore` target, its `APP_STORE` condition and its entitlements, with a CI build of it, unsigned, beside the Developer ID one.
7. **(maintainer)** Decide which App Store Connect API key uploads, with what role, and store it as a secret (or raise the notarization key's role).
8. **(maintainer)** Make the Apple Distribution and Mac Installer Distribution certificates, or enable cloud-managed signing, and store them as secrets.
9. Add the iOS and the Mac App Store archive-and-upload jobs to `release.yml`, and an iOS Release build to CI.
10. Write the privacy policy page on `rfc-reader.mazetti.me`, and a support page or address.
11. **(maintainer)** Lift the hold on releases, and tag the first release that uploads. Install the TestFlight build on a device and test it.
12. Take the screenshots: iPhone, iPad and Mac, in English and German, since the app's chrome is localized.
13. **(maintainer)** Write the description, keywords and subtitle in English and German. Answer the age rating, App Privacy ("Data Not Collected"), export compliance and content-rights questions, and give review notes (no account is needed to use the app).
14. **(maintainer)** Submit for review.

After the first submission:

- Before a release that contains sync (#655), deploy the CloudKit schema to production, and from then on keep schema changes additive.
- Before "Read everything offline" ships, wait for the IETF Trust's answer (#215).
- Before the spring SDK deadline, archive with Xcode 27.
