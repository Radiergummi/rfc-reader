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
  // The app's floors: nothing else consumes this package (#129). No visionOS until
  // there is a visionOS target.
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
      swiftSettings: swiftSettings
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
