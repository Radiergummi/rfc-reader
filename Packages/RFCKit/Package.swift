// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "RFCKit",
  platforms: [
    .iOS(.v18),
    .macOS(.v15),
    .visionOS(.v2),
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
