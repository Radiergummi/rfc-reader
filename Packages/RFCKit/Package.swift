// swift-tools-version: 6.3
import PackageDescription

// One set of language settings for every target, tests included (#129).
let swiftSettings: [SwiftSetting] = [
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
  name: "RFCKit",
  // The app's floors (#129), which its other consumers share: RFCReaderKit declares the
  // same, and corpus-build runs on macOS 26 and Linux. No visionOS until there is a
  // visionOS target.
  platforms: [
    .iOS(.v26),
    .macOS(.v26),
  ],
  products: [
    .library(name: "RFCKit", targets: ["RFCKit"])
  ],
  targets: [
    .target(
      name: "RFCKit",
      // Every unsafe construct the compiler can name is a warning here (#147): the
      // byte scans read `Span`s and the regexes are behind `Pattern` (#146), so the few
      // left are marked `unsafe`, each with its reason, and a new one has to give its own.
      swiftSettings: swiftSettings + [.strictMemorySafety()]
    ),
    .testTarget(
      name: "RFCKitTests",
      dependencies: ["RFCKit"],
      resources: [.copy("Fixtures")],
      swiftSettings: swiftSettings
    ),
  ],
  swiftLanguageModes: [.v6]
)
