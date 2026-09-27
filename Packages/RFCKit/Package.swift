// swift-tools-version: 6.3
import PackageDescription

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
      swiftSettings: [
        .enableUpcomingFeature("ExistentialAny")
      ]
    ),
    .testTarget(
      name: "RFCKitTests",
      dependencies: ["RFCKit"],
      resources: [.copy("Fixtures")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
