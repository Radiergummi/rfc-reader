// swift-tools-version: 6.3
import PackageDescription

// One set of language settings for every target, tests included (#129).
let swiftSettings: [SwiftSetting] = [
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  // The tree has no warnings, and a new one fails the build (#440). Only these
  // targets, never a dependency.
  .treatAllWarnings(as: .error),
]

let package = Package(
  name: "RFCReaderKit",
  defaultLocalization: "en",
  // The app's floors: nothing else consumes this package (#129). No visionOS until
  // there is a visionOS target.
  platforms: [
    .iOS(.v26),
    .macOS(.v26),
  ],
  products: [
    .library(name: "RFCReaderKit", targets: ["RFCReaderKit"])
  ],
  dependencies: [
    .package(path: "../RFCKit")
  ],
  targets: [
    .target(
      name: "RFCReaderKit",
      dependencies: [.product(name: "RFCKit", package: "RFCKit")],
      resources: [.process("Resources")],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "RFCReaderKitTests",
      dependencies: ["RFCReaderKit"],
      resources: [.copy("Fixtures")],
      swiftSettings: swiftSettings
    ),
  ],
  swiftLanguageModes: [.v6]
)
