// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RFCReaderKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "RFCReaderKit", targets: ["RFCReaderKit"]),
    ],
    dependencies: [
        .package(path: "../RFCKit"),
    ],
    targets: [
        .target(
            name: "RFCReaderKit",
            dependencies: [.product(name: "RFCKit", package: "RFCKit")],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
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
