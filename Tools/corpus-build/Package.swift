// swift-tools-version: 6.3
import PackageDescription

// One set of language settings for every target, tests included (#129).
let swiftSettings: [SwiftSetting] = [
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

// Offline pipeline: fetches legacy plain-text RFCs, converts them to RFCXML v3 with
// RFCKit's parsers, and writes a manifest of SHA-256 hashes for the data packs the app
// downloads.
//
// RFCCorpusKit holds what is a pure function of its inputs -- converting one document,
// the report types and the manifest's hashing, the schema check's causes -- so tests
// call it rather than re-implement it. corpus-build is the command line around it:
// arguments, files, concurrency, logging (swift-log) and xmllint.
let package = Package(
  name: "corpus-build",
  // RFCKit's floor.
  platforms: [.macOS(.v26)],
  dependencies: [
    .package(path: "../../Packages/RFCKit"),
    .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
    .package(url: "https://github.com/apple/swift-log", exact: "1.15.1"),
    // SHA-256 for the manifest: CryptoKit on Apple platforms, BoringSSL on Linux.
    .package(url: "https://github.com/apple/swift-crypto", exact: "5.0.0"),
  ],
  targets: [
    .target(
      name: "RFCCorpusKit",
      dependencies: [
        .product(name: "RFCKit", package: "RFCKit"),
        .product(name: "Crypto", package: "swift-crypto"),
      ],
      swiftSettings: swiftSettings
    ),
    .executableTarget(
      name: "corpus-build",
      dependencies: [
        "RFCCorpusKit",
        .product(name: "RFCKit", package: "RFCKit"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Logging", package: "swift-log"),
      ],
      // Unoptimized in a macOS release build: Swift 6.4's crashes in LLVM splitting
      // the commands' async `run`s into their coroutine parts, and `@_optimize(none)`
      // on them compiles but gives every document of a fetch the ID 0 (#371). The
      // command line only orchestrates; the work is RFCKit's and RFCCorpusKit's,
      // which stay optimized. CI's Linux toolchain is not affected. Drop this once a
      // toolchain fixes it.
      swiftSettings: swiftSettings + [
        .unsafeFlags(["-Onone"], .when(platforms: [.macOS], configuration: .release))
      ]
    ),
    .testTarget(
      name: "RFCCorpusKitTests",
      // corpus-build is here to be built, not imported: the command-line tests run
      // the binary, as `make` does.
      dependencies: ["RFCCorpusKit", "corpus-build", .product(name: "RFCKit", package: "RFCKit")],
      swiftSettings: swiftSettings
    ),
  ],
  swiftLanguageModes: [.v6]
)
