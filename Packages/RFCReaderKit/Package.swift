// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "RFCReaderKit",
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
      swiftSettings: [
        .enableUpcomingFeature("ExistentialAny")
      ]
    ),
    .testTarget(
      name: "RFCReaderKitTests",
      dependencies: ["RFCReaderKit"],
      resources: [.copy("Fixtures")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
