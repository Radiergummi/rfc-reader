// swift-tools-version: 6.0
import PackageDescription

// Offline pipeline: fetches legacy plain-text RFCs, converts them to RFCXML v3 with
// RFCKit's parsers, and writes a signed manifest for the data packs the app downloads.
let package = Package(
    name: "corpus-build",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../Packages/RFCKit"),
    ],
    targets: [
        .executableTarget(
            name: "corpus-build",
            dependencies: [.product(name: "RFCKit", package: "RFCKit")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
