// swift-tools-version: 6.3
import PackageDescription

// Offline pipeline: fetches legacy plain-text RFCs, converts them to RFCXML v3 with
// RFCKit's parsers, and writes a signed manifest for the data packs the app downloads.
//
// RFCCorpusKit holds what is a pure function of its inputs -- converting one document,
// the report and manifest types, the schema check's causes -- so tests call it rather
// than re-implement it. corpus-build is the command line around it: arguments, files,
// concurrency, logging and xmllint.
let package = Package(
  name: "corpus-build",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(path: "../../Packages/RFCKit"),
    .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
  ],
  targets: [
    .target(
      name: "RFCCorpusKit",
      dependencies: [.product(name: "RFCKit", package: "RFCKit")]
    ),
    .executableTarget(
      name: "corpus-build",
      dependencies: [
        "RFCCorpusKit",
        .product(name: "RFCKit", package: "RFCKit"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(
      name: "RFCCorpusKitTests",
      // corpus-build is here to be built, not imported: the command-line tests run
      // the binary, as `make` does.
      dependencies: ["RFCCorpusKit", "corpus-build", .product(name: "RFCKit", package: "RFCKit")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
